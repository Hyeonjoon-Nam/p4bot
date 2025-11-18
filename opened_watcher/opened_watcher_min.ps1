# opened_watcher_min.ps1 (config.json-based, no timestamps in Discord output)

param(
  [string]$DepotPath,
  [string]$Snapshot,
  [int]$MaxLinesPerPost = 25,
  [int]$LoopSeconds = 0,
  [switch]$PostSummaryOnChange
)

# --- Locate base dir & load config.json ---
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$BaseDir   = Split-Path -Parent $ScriptDir

$configPath = Join-Path $BaseDir "config.json"
if (-not (Test-Path $configPath)) {
  throw "config.json not found at $configPath"
}
$Config = Get-Content $configPath -Raw | ConvertFrom-Json

# --- P4 ENV from config ---
$env:P4PORT   = $Config.p4.port
$env:P4USER   = $Config.p4.user
$env:P4CLIENT = $Config.p4.client

# --- Defaults from config if not passed ---
if (-not $DepotPath) {
  $DepotPath = [string]$Config.openedWatcher.depotPath
}
if (-not $Snapshot) {
  $Snapshot = Join-Path $BaseDir $Config.openedWatcher.snapshotFile
}

# --- Timezone: system local (for internal calculations) ---
try {
  $TimeZoneId = (Get-TimeZone).Id
} catch {
  $TimeZoneId = [TimeZoneInfo]::Local.Id
}
function ToZone([datetime]$dt){
  try {
    if (-not $dt) { return $null }
    $tz = [TimeZoneInfo]::FindSystemTimeZoneById($TimeZoneId)
    return [TimeZoneInfo]::ConvertTime($dt, $tz)
  } catch {
    return $dt
  }
}

# --- p4 path auto detect ---
$P4Path = "C:\Program Files\Perforce\p4.exe"
if (-not (Test-Path $P4Path)) { $P4Path = "p4" }
function P4 { & $P4Path @args }

# --- Logs / webhook ---
$RuntimeDir = Join-Path $BaseDir "runtime"
if (-not (Test-Path $RuntimeDir)) {
  New-Item -ItemType Directory -Path $RuntimeDir -Force | Out-Null
}

$LogFile = Join-Path $BaseDir $Config.openedWatcher.logFile

function Log([string]$m){
  $ts=(Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
  Add-Content -Path $LogFile -Value "[$ts] $m"
}

$WebhookOverride = [string]$Config.openedWatcher.webhook
if (-not $WebhookOverride) {
  Log "Missing openedWatcher.webhook in config.json"
}

# --- Depot prefixes to trim in output (from config) ---
$TrimPrefixes = @()
if ($Config.openedWatcher.trimPrefixes) {
  $TrimPrefixes = @($Config.openedWatcher.trimPrefixes)
}

# --- Utils ---
function ConvertTo-Hashtable { param($obj)
  if ($null -eq $obj) { return @{} }
  if ($obj -is [hashtable]) { return $obj }
  $ht=@{}
  foreach ($p in $obj.PSObject.Properties) { $ht[$p.Name]=$p.Value }
  return $ht
}

function Load-Snapshot { param([string]$Path)
  if (Test-Path $Path) {
    $raw = Get-Content $Path -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) { return @{} }
    return ConvertTo-Hashtable ($raw | ConvertFrom-Json)
  } else {
    return @{}
  }
}

function Save-Snapshot { param($Data,[string]$Path)
  $dir=[IO.Path]::GetDirectoryName($Path)
  if (-not (Test-Path $dir)) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
  }
  ($Data | ConvertTo-Json -Depth 8) | Set-Content -Path $Path -Encoding UTF8
}

function KeyOf($item){
  '{0}|{1}|{2}' -f $item.depotFile,$item.user,$item.client
}

function Shorten-DepotPath{ param([string]$DepotFile)
  if ([string]::IsNullOrWhiteSpace($DepotFile)) { return $DepotFile }
  $out=$DepotFile
  foreach($p in $TrimPrefixes){
    if ([string]::IsNullOrWhiteSpace($p)) { continue }
    if ($out.StartsWith($p)) {
      $out=$out.Substring($p.Length)
      break
    }
  }
  if ($out.StartsWith('//')){ $out=$out.Substring(2) }
  if ($out.StartsWith('/')){ $out=$out.Substring(1) }
  return $out
}

function Label-Added{ param([string]$a) switch ($a){
  'add'{'[+ add]'}
  'edit'{'[+ edit]'}
  'delete'{'[+ del ]'}
  'move/add'{'[+ mv+ ]'}
  'move/delete'{'[+ mv- ]'}
  default{"[+ $a]"}
} }

function Label-Removed{ param([string]$a) switch ($a){
  'add'{'[- add]'}
  'edit'{'[- edit]'}
  'delete'{'[- del ]'}
  'move/add'{'[- mv+ ]'}
  'move/delete'{'[- mv- ]'}
  default{"[- $a]"}
} }

function Label-State{ param([string]$f,[string]$t) "[state] $f->$t" }

# --- Discord text post ---
function Post-Discord{
  param([string[]]$Lines)
  $url = $WebhookOverride
  if (-not $url) {
    Log "No webhook configured"
    return $false
  }
  $text = ($Lines -join "`n")
  if ([string]::IsNullOrWhiteSpace($text)) { return $false }
  $max = 1900
  $sentAny = $false
  for ($i=0; $i -lt $text.Length; $i += $max) {
    $chunk = $text.Substring($i, [Math]::Min($max, $text.Length - $i))
    $payload = @{ content = $chunk } | ConvertTo-Json -Depth 3 -Compress
    try {
      Invoke-RestMethod -Uri $url -Method Post -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($payload)) | Out-Null
      $sentAny = $true
    } catch {
      Log ("Discord post failed: $($_.Exception.Message)")
      return $sentAny
    }
  }
  return $sentAny
}

# --- Discord embed post (single description, no timestamp) ---
function Post-DiscordEmbedSingle([string[]]$Lines,[string]$Title="Opened files updated"){
  $url = $WebhookOverride
  if (-not $url) {
    Log "No webhook configured"
    return $false
  }
  $desc = ($Lines -join "`n")
  if ($desc.Length -gt 3900) {
    $desc = $desc.Substring(0, 3900) + "…"
  }
  $embed = @{
    title       = ($Title.Substring(0,[Math]::Min(256,$Title.Length)))
    description = $desc
    color       = 5814783
    footer      = @{ text = "Perforce opened watcher" }
  }
  $payload = @{ content = ""; embeds = @($embed) } | ConvertTo-Json -Depth 8 -Compress
  try {
    Invoke-RestMethod -Uri $url -Method Post -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($payload)) | Out-Null
    return $true
  } catch {
    Log ("Discord embed failed: $($_.Exception.Message)")
    return $false
  }
}

# --- Get opened files with -ztag ---
function Get-OpenedTag{ param([string]$Path)
  $out = P4 -ztag opened -a $Path 2>&1
  if (-not $out -or $out.Count -eq 0) {
    $auth = ((P4 login -s 2>&1) -join ' ')
    Log ("opened: 0 lines; login=`"$auth`"")
    return @()
  }
  $items=@()
  $current=@{}
  foreach ($line in $out) {
    if ($line -match '^\.\.\.\s+(\S+)\s+(.*)$') {
      $k=$matches[1]; $v=$matches[2]
      if ($k -eq 'depotFile' -and $current.ContainsKey('depotFile')){
        $items += [pscustomobject]@{
          depotFile=$current['depotFile']
          user     =$current['user']
          client   =$current['client']
          action   =$current['action']
        }
        $current=@{}
      }
      $current[$k]=$v
    }
  }
  if ($current.Count -gt 0 -and $current['depotFile']){
    $items += [pscustomobject]@{
      depotFile=$current['depotFile']
      user     =$current['user']
      client   =$current['client']
      action   =$current['action']
    }
  }
  $items | Where-Object { $_.depotFile -and $_.user -and $_.client -and $_.action }
}

# --- Single loop ---
function Run-Once {
  $now      = Get-Date
  $nowLocal = ToZone $now

  $currItems = Get-OpenedTag -Path $DepotPath

  $prevMap = ConvertTo-Hashtable (Load-Snapshot -Path $Snapshot)
  $currMap = @{}

  foreach ($it in $currItems) {
    $k = KeyOf $it
    if ([string]::IsNullOrEmpty($k)) { continue }
    $first = $now
    if ($prevMap.ContainsKey($k) -and $prevMap[$k].firstSeen) {
      $first = Get-Date $prevMap[$k].firstSeen
    }
    $currMap[$k] = @{
      action   = $it.action
      depotFile= $it.depotFile
      user     = $it.user
      client   = $it.client
      firstSeen= $first
      lastSeen = $now
    }
  }

  $prevKeys=@()
  if ($prevMap -is [hashtable]) { $prevKeys=@($prevMap.Keys) }
  $currKeys=@()
  if ($currMap -is [hashtable]) { $currKeys=@($currMap.Keys) }

  $added=@()
  $removed=@()
  if ($prevKeys -or $currKeys) {
    $cmp = Compare-Object -ReferenceObject $prevKeys -DifferenceObject $currKeys
    $added   = $cmp | Where-Object { $_.SideIndicator -eq '=>' } | ForEach-Object { $_.InputObject }
    $removed = $cmp | Where-Object { $_.SideIndicator -eq '<=' } | ForEach-Object { $_.InputObject }
  }

  $changed=@()
  $common=@($prevKeys | Where-Object { $currMap.ContainsKey($_) })
  foreach ($k in $common) {
    if ($prevMap[$k].action -ne $currMap[$k].action) {
      $changed += $k
    }
  }

  Log ("loop: curr={0} prev={1} added={2} removed={3} changed={4}" -f $currMap.Count,$prevKeys.Count,$added.Count,$removed.Count,$changed.Count)

  # --- Lines describing changes ---
  $changeLines=@()
  foreach ($k in $added) {
    $d=$currMap[$k]
    $u=$d.user
    if(-not $u){$u='unknown'}
    $changeLines += ("{0} {1} — {2}" -f (Label-Added $d.action), $u, (Shorten-DepotPath $d.depotFile))
  }
  foreach ($k in $removed) {
    $d=$prevMap[$k]
    if (-not $d.user){
      $parts=$k -split '\|'
      if($parts.Length -ge 3){$d.user=$parts[1]} else {$d.user='unknown'}
    }
    $changeLines += ("{0} {1} — {2}" -f (Label-Removed $d.action), $d.user, (Shorten-DepotPath $d.depotFile))
  }
  foreach ($k in $changed) {
    $o=$prevMap[$k]
    $n=$currMap[$k]
    $u=$n.user
    if(-not $u){$u=$o.user}
    if(-not $u){$u='unknown'}
    $changeLines += ("{0} {1} — {2}" -f (Label-State $o.action $n.action), $u, (Shorten-DepotPath $n.depotFile))
  }

  if ($changeLines.Count -gt 0) {
    $items=@()
    foreach ($k in $currMap.Keys) {
      $v=$currMap[$k]
      $fsLocal = if ($v.firstSeen) { ToZone (Get-Date $v.firstSeen) } else { $nowLocal }
      $age     = $nowLocal - $fsLocal
      $ageSec  = [int][Math]::Max(0, $age.TotalSeconds)
      $u = $v.user
      if (-not $u) { $u = 'unknown' }
      $items += [pscustomobject]@{
        user   = $u
        short  = (Shorten-DepotPath $v.depotFile)
        ageSec = $ageSec
      }
    }

    $byUser  = $items | Group-Object user | Sort-Object Count -Descending
    $counts  = ($byUser | ForEach-Object { "{0}({1})" -f $_.Name,$_.Count }) -join " · "

    $payload = @()
    $payload += ($changeLines | Select-Object -First $MaxLinesPerPost)
    $payload += ""
    $payload += ("active {0} files / {1} users" -f $items.Count, $byUser.Count)
    $payload += $counts
    $payload += ""

    $PerUserMax    = 5
    $TotalMaxLines = 40
    $linesUsed     = 0
    $firstUser     = $true
    foreach ($g in $byUser) {
      if ($linesUsed -ge $TotalMaxLines) { break }
      if (-not $firstUser) { $payload += "" }
      $firstUser = $false

      $payload += ("**{0}**" -f $g.Name)
      $linesUsed++
      $list = $g.Group | Sort-Object ageSec -Descending | Select-Object -First $PerUserMax
      foreach ($it in $list) {
        if ($linesUsed -ge $TotalMaxLines) { break }
        $payload += ("• {0}" -f $it.short)
        $linesUsed++
      }
      if ($g.Count -gt $PerUserMax -and $linesUsed -lt $TotalMaxLines) {
        $payload += ("• +{0} more" -f ($g.Count - $PerUserMax))
        $linesUsed++
      }
    }

    $ok = Post-DiscordEmbedSingle $payload "Opened files updated"
    if ($ok) {
      Log ("posted(embed): events={0}; totalActive={1}" -f $changeLines.Count,$currMap.Count)
    }
    else {
      $ok2 = Post-Discord -Lines $payload
      if ($ok2) {
        Log ("posted(text): events={0}; totalActive={1}" -f $changeLines.Count,$currMap.Count)
      } else {
        Log ("post failed (both): events={0}; totalActive={1}" -f $changeLines.Count,$currMap.Count)
      }
    }
  }

  Save-Snapshot -Data $currMap -Path $Snapshot
  return $changeLines.Count
}

# --- Entry point ---
[Console]::OutputEncoding = [Text.Encoding]::UTF8
try {
  $null = P4 -V 2>$null
} catch {
  Log "p4 not found: $P4Path"
  throw
}
Log ("startup: P4PORT={0} P4USER={1} P4CLIENT={2} DepotPath={3}" -f $env:P4PORT,$env:P4USER,$env:P4CLIENT,$DepotPath)
try {
  Log ("login: " + ((P4 login -s 2>&1) -join ' '))
} catch {}

if ($LoopSeconds -gt 0) {
  while ($true) {
    [void](Run-Once)
    Start-Sleep -Seconds $LoopSeconds
  }
} else {
  [void](Run-Once)
}
