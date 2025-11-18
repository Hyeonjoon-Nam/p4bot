param(
    [int]$IntervalSeconds,
    [string]$DepotFilter
)

# --- P4 path auto detect ---
$P4Path = "C:\Program Files\Perforce\p4.exe"
if (-not (Test-Path $P4Path)) { $P4Path = "p4" }

function P4 {
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Args
    )
    & $P4Path @Args
}

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

# --- Parameters default from config if not passed ---
if (-not $IntervalSeconds) {
    $IntervalSeconds = [int]$Config.poller.intervalSeconds
}
if (-not $DepotFilter) {
    $DepotFilter = [string]$Config.poller.depotFilter
}

# --- Paths from config ---
$RuntimeDir = Join-Path $BaseDir "runtime"
if (-not (Test-Path $RuntimeDir)) {
    New-Item -ItemType Directory -Path $RuntimeDir -Force | Out-Null
}

$StateFile = Join-Path $BaseDir $Config.poller.stateFile
$LogFile   = Join-Path $BaseDir $Config.poller.logFile

function Log([string]$m) {
    $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    Add-Content -Path $LogFile -Value "[$ts] $m"
}

# --- Webhook and routing from config ---
$WEBHOOK = [string]$Config.poller.webhook
if (-not $WEBHOOK) {
    Log "Missing poller.webhook in config.json"
    throw "Missing poller.webhook in config.json"
}

$SWARM = $null
if ($Config.poller.swarmBase) {
    $tmp = [string]$Config.poller.swarmBase
    if ($tmp.Trim().Length -gt 0) {
        $SWARM = $tmp.Trim().TrimEnd('/')
    }
}

$UserRouting = $null
if ($Config.poller.userRouting) {
    $UserRouting = $Config.poller.userRouting
}

# --- Prefix trimming config ---
$TrimPrefixes = @()
if ($Config.poller.trimPrefixes) {
    $TrimPrefixes = @($Config.poller.trimPrefixes)
}

# --- Preflight ---
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
try {
    $null = P4 -V 2>$null
} catch {
    Log "p4 not found: $P4Path"
    throw
}

if (!(Test-Path $StateFile)) {
    "0" | Out-File -FilePath $StateFile -Encoding ascii
}

try {
    $lastKnown = [int](Get-Content $StateFile | Select-Object -First 1)
} catch {
    $lastKnown = 0
}
Log "poller start; p4=$P4Path; lastKnown=$lastKnown; depotFilter=$DepotFilter"

# --- Helpers ---
function Send-DiscordEmbed($payloadObj, $uri) {
    $json = $payloadObj | ConvertTo-Json -Depth 8 -Compress
    try {
        Invoke-RestMethod -Uri $uri -Method Post -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($json)) | Out-Null
        return $true
    } catch {
        Log "Discord send failed: $($_.Exception.Message)"
        return $false
    }
}

function Strip-Prefix($path) {
    if ([string]::IsNullOrWhiteSpace($path)) { return $path }

    $p = $path.Trim().Replace('\', '/')

    foreach ($pref in $TrimPrefixes) {
        if ([string]::IsNullOrWhiteSpace($pref)) { continue }

        $norm = $pref.Trim().Replace('\', '/').TrimEnd('/')
        $rx   = '^' + [regex]::Escape($norm) + '(/|$)'

        if ($p -match $rx) {
            return ($p -replace $rx, '')
        }
    }

    return $path.Trim()
}

function Get-ServerOffset {
    # Example: "Server date: 2025/10/21 15:37:24 -0700 PDT"
    $info = P4 info 2>$null
    $line = $info | Where-Object { $_ -like 'Server date:*' } | Select-Object -First 1
    if ($line -and ($line -match 'Server date:\s+\d{4}/\d{2}/\d{2}\s+\d{2}:\d{2}:\d{2}\s+([+-]\d{4})')) {
        $off  = $Matches[1]
        $sign = 1
        if ($off.StartsWith('-')) { $sign = -1 }
        $hh = [int]$off.Substring(1, 2)
        $mm = [int]$off.Substring(3, 2)
        return [TimeSpan]::FromMinutes($sign * (60 * $hh + $mm))
    }
    return [datetimeoffset]::Now.Offset
}

# --- main loop ---
while ($true) {
    try {
        $serverOffset = Get-ServerOffset
        $changesRaw   = P4 changes -s submitted -m 20 $DepotFilter 2>$null

        $nums = @()
        foreach ($line in $changesRaw) {
            if ($line -match "Change\s+(\d+)\s+") {
                $nums += [int]$Matches[1]
            }
        }
        $nums = $nums | Sort-Object
        $newOnes = $nums | Where-Object { $_ -gt $lastKnown }
        if ($newOnes.Count -gt 0) {
            Log "new changes: $($newOnes -join ', ')"
        }

        foreach ($chg in $newOnes) {
            $descLines = P4 describe -s $chg 2>$null
            if (-not $descLines) { continue }
            $ztag = P4 -ztag describe -s $chg 2>$null

            # meta
            $by   = "(unknown)"
            $when = ""
            foreach ($l in $descLines) {
                if ($l -match ("^Change\s+" + $chg + "\s+by\s+(.+?)\s+on\s+(\d{4}/\d{2}/\d{2}\s+\d{2}:\d{2}:\d{2})")) {
                    $by   = $Matches[1]
                    $when = $Matches[2]
                    break
                }
            }
            if ($by -match '^([^@]+)@') { $by = $Matches[1] }
            $by = $by.Trim()

            # description block
            $fullMessage = "(no description)"

            $descBlock  = New-Object System.Collections.Generic.List[string]
            $seenHeader = $false
            foreach ($line in $descLines) {
                if (-not $seenHeader) {
                    if ($line -match ("^Change\s+" + $chg + "\s+by\s+")) {
                        $seenHeader = $true
                    }
                    continue
                }

                if ($line -match "^Affected files") {
                    break
                }

                if ($descBlock.Count -eq 0 -and [string]::IsNullOrWhiteSpace($line)) {
                    continue
                }

                $descBlock.Add($line.TrimEnd())
            }

            if ($descBlock.Count -gt 0) {
                $fullMessage = ($descBlock -join "`n").Trim()
            }

            # files
            $files = New-Object System.Collections.Generic.List[string]
            foreach ($l in $ztag) {
                if ($l -match '^\.\.\.\s+depotFile\s+(.+)$') {
                    $files.Add($Matches[1])
                }
            }
            if ($files.Count -eq 0) {
                $inFiles = $false
                foreach ($l in $descLines) {
                    if ($l -match "^Affected files") { $inFiles = $true; continue }
                    if ($inFiles) {
                        if ($l -match "^Differences" -or $l -match "^\s*$") { $inFiles = $false; break }
                        $trim = $l.ToString().Trim()
                        if ($trim.StartsWith("... ")) { $trim = $trim.Substring(4) }
                        if ($trim -match '^(//.+?)(\s|#)') {
                            $files.Add($Matches[1])
                        } else {
                            $files.Add($trim)
                        }
                    }
                }
            }
            if ($files.Count -eq 0) {
                $filesAt = P4 files ("@=$chg") 2>$null
                foreach ($l in $filesAt) {
                    if ($l -match '^(//\S+)#\d+\s+-\s+\w+\s+change\s+\d+') {
                        $files.Add($Matches[1])
                    }
                    elseif ($l -match '^(//\S+)') {
                        $files.Add($Matches[1])
                    }
                }
            }
            $displayFiles = @()
            foreach ($f in $files) { $displayFiles += (Strip-Prefix $f) }

            # files field
            $maxShow = 6
            $shown   = $displayFiles | Select-Object -First $maxShow
            $more    = [Math]::Max(0, $displayFiles.Count - $shown.Count)
            $filesText = "(no files)"
            if ($shown.Count -gt 0) {
                $filesText  = '```' + "`n" + ($shown -join "`n")
                if ($more -gt 0) { $filesText += "`n+" + $more + " more" }
                $filesText += "`n" + '```'
            }

            # timestamp: server -> UTC
            $ts = $null
            try {
                $dt  = [datetime]::ParseExact($when, 'yyyy/MM/dd HH:mm:ss', $null)
                $dto = New-Object System.DateTimeOffset($dt, $serverOffset)
                $ts  = $dto.ToUniversalTime().ToString("o")
            } catch { }

            $color = 3447003
            $url   = $null
            if ($SWARM) { $url = "$SWARM/changes/$chg" }

            # title: first line of description
            $titleText = $fullMessage
            if ($titleText -match "`n") {
                $titleText = $titleText.Split("`n")[0]
            }
            if ($titleText.Length -gt 256) { $titleText = $titleText.Substring(0, 256) }

            # body text
            $bodyText = $fullMessage
            if ($bodyText.Length -gt 4000) {
                $bodyText = $bodyText.Substring(0, 4000) + "`n…"
            }

            $embed = @{
                title       = $titleText
                description = $bodyText
                color       = $color
                url         = $url
                footer      = @{ text = "Change #$chg" }
                timestamp   = $ts
                fields      = @(
                    @{ name = "User";  value = $by;        inline = $true  },
                    @{ name = "Files"; value = $filesText; inline = $false }
                )
            }
            $payload = @{ content = ""; embeds = @($embed) }

            $publicOk = Send-DiscordEmbed $payload $WEBHOOK

            # personal routing (optional)
            try {
                $personalWebhook = $null
                if ($UserRouting -ne $null) {
                    if ($UserRouting -is [System.Collections.IDictionary]) {
                        if ($UserRouting.Contains($by)) { $personalWebhook = [string]$UserRouting[$by] }
                    } else {
                        $prop = $UserRouting.PSObject.Properties[$by]
                        if ($prop -and $prop.Value) { $personalWebhook = [string]$prop.Value }
                    }
                }
                if ($personalWebhook) { [void](Send-DiscordEmbed $payload $personalWebhook) }
            } catch { }

            if ($publicOk) {
                $lastKnown = [Math]::Max($lastKnown, $chg)
                Set-Content -Path $StateFile -Value $lastKnown -Encoding ascii
                Log "posted change $chg; lastKnown=$lastKnown"
            } else {
                Log "public send failed for change $chg"
                Start-Sleep -Seconds 5
            }
        }
    } catch {
        Log "loop error: $($_.Exception.Message)"
    }
    Start-Sleep -Seconds $IntervalSeconds
}
