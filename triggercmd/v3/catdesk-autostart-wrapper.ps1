[CmdletBinding()]
param(
    [switch]$Startup
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$userRoot   = "C:\Users\mozar"
$control    = Join-Path $userRoot "TriggerCMD-Scripts\Control"
$autonomy   = Join-Path $userRoot "TriggerCMD-Scripts\Autonomy"
$urlFile    = Join-Path $autonomy "catdesk-url.txt"
$configFile = Join-Path $userRoot ".catdesk\config.toml"
$core       = Join-Path $control "catdesk-autostart-core.ps1"
$port       = 3200

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

function Get-CatDeskUrl {
    if (Test-Path -LiteralPath $urlFile -PathType Leaf) {
        $saved = (Get-Content -LiteralPath $urlFile -Raw).Trim()
        if (-not [string]::IsNullOrWhiteSpace($saved)) { return $saved }
    }

    if (Test-Path -LiteralPath $configFile -PathType Leaf) {
        $config = Get-Content -LiteralPath $configFile -Raw
        $slug = $null
        $domain = $null
        if ($config -match '(?m)^\s*mcpSlug\s*=\s*"([^"]+)"') { $slug = $Matches[1] }
        if ($config -match '(?m)^\s*ngrokDomain\s*=\s*"([^"]+)"') { $domain = $Matches[1] }
        if ($slug -and $domain) { return "https://$domain/$slug/mcp" }
    }

    return "http://127.0.0.1:$port"
}

function Open-CatDeskBrowser {
    param([Parameter(Mandatory)][string]$Url)
    Start-Process $Url
    Write-Output "OPENED $Url"
}

if (Test-Port -Port $port) {
    Open-CatDeskBrowser -Url (Get-CatDeskUrl)
    exit 0
}

if (-not (Test-Path -LiteralPath $core -PathType Leaf)) {
    throw "CatDesk core launcher missing: $core"
}

$coreArgs = @(
    "-NoProfile",
    "-ExecutionPolicy","Bypass",
    "-File",$core
)
if ($Startup) { $coreArgs += "-Startup" }

$launch = Start-Process powershell.exe -WindowStyle Hidden -ArgumentList $coreArgs -Wait -PassThru
if ($launch.ExitCode -ne 0) {
    throw "CatDesk core launcher exited $($launch.ExitCode)."
}
if (-not (Test-Port -Port $port)) {
    throw "CatDesk did not bind port $port."
}

# Ensure future logins use the idempotent wrapper rather than the core launcher.
$startupFolder = [Environment]::GetFolderPath("Startup")
$startupCmd = Join-Path $startupFolder "Start CatDesk.cmd"
$startupText = @"
@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "$PSCommandPath" -Startup
"@
[IO.File]::WriteAllText($startupCmd,$startupText,[Text.ASCIIEncoding]::new())

Open-CatDeskBrowser -Url (Get-CatDeskUrl)
exit 0
