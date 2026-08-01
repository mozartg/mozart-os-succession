[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet(
        "control_status",
        "job_status",
        "job_result",
        "workspace_list",
        "workspace_read",
        "system_health",
        "process_find",
        "port_check",
        "command_find",
        "catdesk_status",
        "catdesk_autostart",
        "catdesk_probe",
        "playwright_status",
        "browser_status",
        "approved_inventory",
        "media_factory_bootstrap",
        "trigger_reload"
    )]
    [string]$Task,

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Input
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$userRoot     = "C:\Users\mozar"
$triggerData  = Join-Path $userRoot ".TRIGGERcmdData"
$controlRoot  = Join-Path $userRoot "TriggerCMD-Scripts\Control"
$jobsRoot     = Join-Path $controlRoot "Jobs"
$workerPath   = Join-Path $controlRoot "worker.ps1"
$catdeskStart = Join-Path $controlRoot "catdesk-autostart.ps1"
$catdeskState = Join-Path $userRoot "TriggerCMD-Scripts\Autonomy\catdesk-autostart-status.json"
$catdeskUrl   = Join-Path $userRoot "TriggerCMD-Scripts\Autonomy\catdesk-url.txt"
$sendResult   = Join-Path $triggerData "sendresult.bat"

New-Item -ItemType Directory -Force -Path $jobsRoot | Out-Null

function Send-Now {
    param([Parameter(Mandatory)][string]$Text)
    $clean = ($Text -replace "`r?`n"," | ").Trim()
    if ($clean.Length -gt 850) { $clean = $clean.Substring(0,850) }
    if (Test-Path -LiteralPath $sendResult -PathType Leaf) {
        & $sendResult $clean | Out-Null
    }
}

function Test-LocalPort {
    param([int]$Port)
    $client = [Net.Sockets.TcpClient]::new()
    try {
        $iar = $client.BeginConnect("127.0.0.1",$Port,$null,$null)
        if (-not $iar.AsyncWaitHandle.WaitOne(700,$false)) { return $false }
        $client.EndConnect($iar)
        return $true
    } catch { return $false } finally { $client.Dispose() }
}

function Save-NewJob {
    param([string]$Name,[string]$InputText)
    $id = "{0}-{1}" -f (Get-Date -Format "yyyyMMddHHmmss"),([guid]::NewGuid().ToString("N").Substring(0,8))
    $path = Join-Path $jobsRoot "$id.json"
    $job = [ordered]@{
        id=$id; task=$Name; input=$InputText; status="queued"
        createdAt=(Get-Date).ToString("o"); startedAt=$null; completedAt=$null
        exitCode=$null; result=$null; error=$null
    }
    [IO.File]::WriteAllText($path,($job | ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($false))
    return [pscustomobject]@{Id=$id;Path=$path}
}

$joinedInput = (($Input | Where-Object { $null -ne $_ }) -join " ").Trim()

try {
    switch ($Task) {
        "control_status" {
            Send-Now "OK control_status :: FleetVersion=3.1.6; Dispatcher=ready"
        }
        "catdesk_autostart" {
            if (-not (Test-Path -LiteralPath $catdeskStart -PathType Leaf)) { throw "CatDesk autostart script missing." }
            Send-Now "OK catdesk_autostart :: scheduled"
            Start-Process powershell.exe -WindowStyle Hidden -ArgumentList @(
                "-NoProfile","-ExecutionPolicy","Bypass","-File",$catdeskStart
            )
        }
        "catdesk_probe" {
            $online = Test-LocalPort -Port 3200
            $url = if (Test-Path -LiteralPath $catdeskUrl) { (Get-Content -LiteralPath $catdeskUrl -Raw).Trim() } else { "--" }
            $phase = "--"
            $errorText = ""
            if (Test-Path -LiteralPath $catdeskState) {
                $state = Get-Content -LiteralPath $catdeskState -Raw | ConvertFrom-Json
                $phase = [string]$state.phase
                $errorText = [string]$state.error
            }
            Send-Now "OK catdesk_probe :: Online=$online; Phase=$phase; URL=$url; Error=$errorText"
        }
        "job_status" {
            $path = Join-Path $jobsRoot "$joinedInput.json"
            if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Job not found." }
            $job = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
            Send-Now "OK job_status :: Id=$($job.id); Task=$($job.task); Status=$($job.status); Exit=$($job.exitCode); Created=$($job.createdAt); Completed=$($job.completedAt)"
        }
        "job_result" {
            $path = Join-Path $jobsRoot "$joinedInput.json"
            if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Job not found." }
            $job = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
            $value = if ($job.status -eq "completed") { $job.result } elseif ($job.status -eq "failed") { $job.error } else { "Status=$($job.status)" }
            Send-Now "OK job_result :: Id=$($job.id); $value"
        }
        "trigger_reload" {
            Send-Now "OK trigger_reload :: Restart scheduled"
            $agentExe = Get-ChildItem -LiteralPath (Join-Path $env:LOCALAPPDATA "TRIGGERcmdAgent") -Filter "TRIGGERcmdAgent.exe" -File -Recurse |
                Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
            $code = "Start-Sleep 3; Get-Process TRIGGERcmdAgent -ErrorAction SilentlyContinue | Stop-Process -Force; Start-Sleep 2; Start-Process '$agentExe'"
            Start-Process powershell.exe -WindowStyle Hidden -ArgumentList @("-NoProfile","-ExecutionPolicy","Bypass","-Command",$code)
        }
        default {
            $job = Save-NewJob -Name $Task -InputText $joinedInput
            Send-Now "QUEUED $Task :: Job=$($job.Id)"
            Start-Process powershell.exe -WindowStyle Hidden -ArgumentList @(
                "-NoProfile","-NonInteractive","-ExecutionPolicy","RemoteSigned",
                "-File",$workerPath,"-JobPath",$job.Path
            )
        }
    }
    exit 0
}
catch {
    Send-Now "FAILED $Task :: $($_.Exception.Message)"
    exit 1
}
