# canwork_task.ps1
# Register scheduled task "P4CanWorkBot"
# - Runs p4_canwork_bot.py at user logon
# - Uses pythonw.exe (no console window)

# --- Locate base dir & load config.json ---
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$baseDir   = Split-Path -Parent $scriptDir

$configPath = Join-Path $baseDir "config.json"
if (-not (Test-Path $configPath)) {
    throw "config.json not found at $configPath"
}
$Config = Get-Content $configPath -Raw | ConvertFrom-Json

$taskName  = $Config.canworkBot.taskName
$botScript = Join-Path $scriptDir $Config.canworkBot.scriptName

# 1) Remove existing task if it exists
$existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($existing) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
}

# 2) Locate pythonw.exe
$pythonw = $Config.canworkBot.pythonwPath
if (-not (Test-Path $pythonw)) {
    $pythonw = 'pythonw.exe'    # fallback: rely on PATH
}

# 3) Define action (run pythonw with the bot script)
$action = New-ScheduledTaskAction `
    -Execute $pythonw `
    -Argument "`"$botScript`""

# 4) Trigger: at user logon
$trigger = New-ScheduledTaskTrigger -AtLogOn

# 5) Run as current user, normal privileges
$principal = New-ScheduledTaskPrincipal `
    -UserId $env:USERNAME `
    -LogonType Interactive `
    -RunLevel Limited

# 6) Register scheduled task
$task = Register-ScheduledTask `
    -TaskName $taskName `
    -Action $action `
    -Trigger $trigger `
    -Principal $principal `
    -Description 'Discord /canwork bot for Perforce'

$task | Select TaskName, State, @{Name='Execute';Expression={$_.Actions.Execute}}, @{Name='Args';Expression={$_.Actions.Arguments}}
Write-Host "Registered new scheduled task '$taskName'."
