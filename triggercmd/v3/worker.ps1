[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$JobPath
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$modulePath = "C:\Users\mozar\TriggerCMD-Scripts\Control\tasks.psm1"
Import-Module $modulePath -Force

function Save-Job {
    param([Parameter(Mandatory)]$Job)
    $temp = "$JobPath.tmp"
    [IO.File]::WriteAllText($temp,($Job | ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temp -Destination $JobPath -Force
}

try {
    $job = Get-Content -LiteralPath $JobPath -Raw | ConvertFrom-Json
    $job.status = "running"
    $job.startedAt = (Get-Date).ToString("o")
    Save-Job $job

    $result = Invoke-ControlTask -Task ([string]$job.task) -InputText ([string]$job.input)

    $job = Get-Content -LiteralPath $JobPath -Raw | ConvertFrom-Json
    $job.status = "completed"
    $job.completedAt = (Get-Date).ToString("o")
    $job.exitCode = 0
    $job.result = [string]$result
    Save-Job $job
    exit 0
}
catch {
    try {
        $job = Get-Content -LiteralPath $JobPath -Raw | ConvertFrom-Json
        $job.status = "failed"
        $job.completedAt = (Get-Date).ToString("o")
        $job.exitCode = 1
        $job.error = $_.Exception.Message
        Save-Job $job
    } catch {}
    exit 1
}
