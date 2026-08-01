[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$source = "https://raw.githubusercontent.com/mozartg/mozart-os-succession/main/triggercmd/v3/bootstrap.ps1"
$expectedHash = "f9b93288ee437840476ed4eb30500824cdaba2bcf99d519a03b223620eaa5966"
$destination = "C:\Users\mozar\TriggerCMD-Scripts\bootstrap.ps1"
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$temp = "$destination.v3-$stamp.download"
$backup = "$destination.before-v3-$stamp"

New-Item -ItemType Directory -Force -Path (Split-Path $destination -Parent) | Out-Null

try {
    Invoke-WebRequest -Uri ($source + "?t=" + [uri]::EscapeDataString($stamp)) -OutFile $temp -UseBasicParsing

    $actual = (Get-FileHash -LiteralPath $temp -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $expectedHash) { throw "Bootstrap hash validation failed." }

    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($temp,[ref]$tokens,[ref]$errors) | Out-Null
    if ($errors.Count -gt 0) { throw "Bootstrap syntax validation failed: $($errors[0].Message)" }

    if (Test-Path -LiteralPath $destination -PathType Leaf) {
        Copy-Item -LiteralPath $destination -Destination $backup -Force
    }

    Move-Item -LiteralPath $temp -Destination $destination -Force
    & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy RemoteSigned -File $destination
    if ($LASTEXITCODE -ne 0) { throw "Bootstrap v3 returned exit code $LASTEXITCODE." }

    Write-Host "CONTROL PLANE V3 INSTALLED"
    Write-Host "Bootstrap: $destination"
    Write-Host "Backup: $backup"
}
catch {
    Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $backup -PathType Leaf) {
        Copy-Item -LiteralPath $backup -Destination $destination -Force
    }
    throw
}
