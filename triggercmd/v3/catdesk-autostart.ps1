[CmdletBinding()]
param(
    [switch]$Startup
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$userRoot   = "C:\Users\mozar"
$base       = Join-Path $userRoot "TriggerCMD-Scripts"
$control    = Join-Path $base "Control"
$autonomy   = Join-Path $base "Autonomy"
$secrets    = Join-Path $base "Secrets"
$logs       = Join-Path $base "Logs"
$tokenFile  = Join-Path $secrets "ngrok-token.txt"
$configDir  = Join-Path $userRoot ".catdesk"
$configFile = Join-Path $configDir "config.toml"
$launcher   = Join-Path $autonomy "start-catdesk.cmd"
$statusFile = Join-Path $autonomy "catdesk-autostart-status.json"
$urlFile    = Join-Path $autonomy "catdesk-url.txt"
$domain     = "emphatic-tux-ungodly.ngrok-free.dev"
$port       = 3200
$workspace  = $userRoot
$stamp      = Get-Date -Format "yyyyMMdd-HHmmss"
$logFile    = Join-Path $logs "catdesk-autostart-$stamp.log"

New-Item -ItemType Directory -Force -Path $control,$autonomy,$secrets,$logs,$configDir | Out-Null

function Write-Log {
    param([Parameter(Mandatory)][string]$Message)
    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"),$Message
    [IO.File]::AppendAllText($logFile,$line + [Environment]::NewLine,[Text.UTF8Encoding]::new($false))
}

function Escape-Toml {
    param([Parameter(Mandatory)][string]$Value)
    return $Value.Replace('\','\\').Replace('"','\"').Replace("`r",'\r').Replace("`n",'\n')
}

function Test-Port {
    param([int]$Port,[int]$TimeoutMs = 800)
    $client = [Net.Sockets.TcpClient]::new()
    try {
        $iar = $client.BeginConnect("127.0.0.1",$Port,$null,$null)
        if (-not $iar.AsyncWaitHandle.WaitOne($TimeoutMs,$false)) { return $false }
        $client.EndConnect($iar)
        return $true
    } catch {
        return $false
    } finally {
        $client.Dispose()
    }
}

function Save-Status {
    param(
        [string]$Phase,
        [bool]$Online,
        [string]$Url,
        [string]$ErrorText = ""
    )
    $proc = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -ieq "catdesk.exe" -or
        ($_.Name -ieq "node.exe" -and $_.CommandLine -match "(?i)catdesk")
    } | Select-Object Name,ProcessId,ExecutablePath,CommandLine)
    $status = [ordered]@{
        checkedAt = (Get-Date).ToString("o")
        phase = $Phase
        online = $Online
        port = $port
        processCount = $proc.Count
        processes = $proc
        connectorUrl = $Url
        error = $ErrorText
        log = $logFile
    }
    [IO.File]::WriteAllText($statusFile,($status | ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($false))
}

try {
    Write-Log "CatDesk autonomous start began. Startup=$Startup"

    if (-not (Test-Path -LiteralPath $tokenFile -PathType Leaf)) {
        throw "Token file missing: $tokenFile"
    }
    $token = (Get-Content -LiteralPath $tokenFile -Raw).Trim()
    if ([string]::IsNullOrWhiteSpace($token)) {
        throw "Token file is empty."
    }

    # Stop CatDesk before any possible package update. Windows locks the
    # installed binary while it is running, which causes npm EBUSY.
    Get-Process catdesk -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -ieq "node.exe" -and $_.CommandLine -match "(?i)catdesk"
    } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Seconds 2

    $env:Path = [Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                [Environment]::GetEnvironmentVariable("Path","User") + ";" +
                "$env:APPDATA\npm"

    $catdesk = @(
        (Get-Command catdesk.cmd -ErrorAction SilentlyContinue).Source,
        "$env:APPDATA\npm\catdesk.cmd"
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } | Select-Object -First 1

    # Normal startups reuse the installed official package. Install only when
    # the command is missing; do not upgrade a live global package in place.
    if (-not $catdesk) {
        $npm = Get-Command npm.cmd -ErrorAction SilentlyContinue
        if (-not $npm) { throw "npm.cmd not found." }
        & $npm.Source install -g catdesk@latest *> $null
        if ($LASTEXITCODE -ne 0) { throw "npm install returned exit code $LASTEXITCODE." }

        $env:Path = [Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                    [Environment]::GetEnvironmentVariable("Path","User") + ";" +
                    "$env:APPDATA\npm"
        $catdesk = @(
            (Get-Command catdesk.cmd -ErrorAction SilentlyContinue).Source,
            "$env:APPDATA\npm\catdesk.cmd"
        ) | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } | Select-Object -First 1
    }
    if (-not $catdesk) { throw "Official catdesk.cmd not found." }

    $slug = $null
    if (Test-Path -LiteralPath $configFile -PathType Leaf) {
        $existing = Get-Content -LiteralPath $configFile -Raw
        if ($existing -match '(?m)^\s*mcpSlug\s*=\s*"([^"]+)"') { $slug = $Matches[1] }
        Copy-Item -LiteralPath $configFile -Destination "$configFile.backup-$stamp" -Force
    }
    if ([string]::IsNullOrWhiteSpace($slug)) { $slug = [Guid]::NewGuid().ToString("N") }

    $config = @"
ngrokAuthtoken = "$(Escape-Toml $token)"
mcpSlug = "$(Escape-Toml $slug)"
ngrokDomain = "$(Escape-Toml $domain)"
agentsPathMode = "default"
tokenStatsLayout = "right"
showDetailMode = "expanded"
setCatdeskAsCoAuthor = false
theme = "concise"
mode = "computer"
toolMode = "multiTools"

[usageTotals]
inputTokens = 0
outputTokens = 0
totalTokens = 0
toolCallCount = 0
"@
    [IO.File]::WriteAllText($configFile,$config,[Text.UTF8Encoding]::new($false))
    Remove-Variable token -ErrorAction SilentlyContinue

    $launcherText = @"
@echo off
title CatDesk MCP Server
set "PORT=$port"
set "WORKSPACE_ROOT=$workspace"
cd /d "$workspace"
call "$catdesk"
"@
    [IO.File]::WriteAllText($launcher,$launcherText,[Text.ASCIIEncoding]::new())

    $args = '/k call "' + $launcher + '"'
    $window = Start-Process -FilePath $env:ComSpec -ArgumentList $args -WorkingDirectory $workspace -PassThru
    Write-Log "Started terminal PID=$($window.Id)."

    # CatDesk always opens the mode-selection TUI, even with a saved mode.
    # Inject the '1' key directly into the console buffer without requiring
    # foreground focus or human interaction.
    Start-Sleep -Seconds 3
    $injector = Join-Path $control "catdesk-console-input.ps1"
    if (-not (Test-Path -LiteralPath $injector -PathType Leaf)) {
        throw "Console input injector missing: $injector"
    }
    & $injector -ProcessId ([uint32]$window.Id)
    Write-Log "Injected mode-selection key 1 into CatDesk console."

    $online = $false
    for ($i=0; $i -lt 60; $i++) {
        if (Test-Port -Port $port) { $online = $true; break }
        Start-Sleep -Seconds 1
    }

    $url = "https://$domain/$slug/mcp"
    [IO.File]::WriteAllText($urlFile,$url,[Text.UTF8Encoding]::new($false))

    if (-not $online) {
        Save-Status -Phase "mode-key-sent-port-closed" -Online $false -Url $url -ErrorText "CatDesk did not bind port 3200 after automated mode selection."
        throw "CatDesk did not bind port 3200 after automated mode selection."
    }

    # Persist autonomous startup after success.
    $startupFolder = [Environment]::GetFolderPath("Startup")
    $startupCmd = Join-Path $startupFolder "Start CatDesk.cmd"
    $startupText = @"
@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "$PSCommandPath" -Startup
"@
    [IO.File]::WriteAllText($startupCmd,$startupText,[Text.ASCIIEncoding]::new())

    Save-Status -Phase "online" -Online $true -Url $url
    Write-Log "CatDesk online at $url"
    exit 0
}
catch {
    $message = $_.Exception.Message
    Write-Log "FAILED: $message"
    $url = ""
    try {
        if (Test-Path -LiteralPath $urlFile) { $url = (Get-Content -LiteralPath $urlFile -Raw).Trim() }
    } catch {}
    Save-Status -Phase "failed" -Online $false -Url $url -ErrorText $message
    exit 1
}
