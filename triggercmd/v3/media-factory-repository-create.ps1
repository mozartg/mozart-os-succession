[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$coreUrl = "https://raw.githubusercontent.com/mozartg/mozart-os-succession/32d4845f71d278511c435c8d805fc6089f8ccdbc/triggercmd/v3/media-factory-repository-create.ps1"
$corePath = Join-Path $env:TEMP ("media-factory-repository-create-core-{0}.ps1" -f ([guid]::NewGuid().ToString("N")))
$inventoryInstaller = "C:\Users\mozar\TriggerCMD-Scripts\Control\system-inventory-installer.ps1"
$inventoryPath = "C:\Users\mozar\TriggerCMD-Scripts\Control\system-inventory.ps1"

try {
    Invoke-WebRequest -Uri $coreUrl -OutFile $corePath -UseBasicParsing
    $coreOutput = @(& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy RemoteSigned -File $corePath 2>&1)
    $coreCode = $LASTEXITCODE
    if ($coreCode -ne 0) {
        throw "Media Factory core exited $coreCode: $(($coreOutput | Out-String).Trim())"
    }
    if (-not (Test-Path -LiteralPath $inventoryInstaller -PathType Leaf)) {
        throw "System inventory installer is missing: $inventoryInstaller"
    }
    $installOutput = @(& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy RemoteSigned -File $inventoryInstaller 2>&1)
    $installCode = $LASTEXITCODE
    if ($installCode -ne 0) {
        throw "System inventory installer exited $installCode: $(($installOutput | Out-String).Trim())"
    }
    if (-not (Test-Path -LiteralPath $inventoryPath -PathType Leaf)) {
        throw "System inventory collector was not created: $inventoryPath"
    }
    $inventoryOutput = @(& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy RemoteSigned -File $inventoryPath 2>&1)
    $inventoryCode = $LASTEXITCODE
    if ($inventoryCode -ne 0) {
        throw "System inventory collector exited $inventoryCode: $(($inventoryOutput | Out-String).Trim())"
    }
    Write-Output "MediaFactory=$(($coreOutput | Out-String).Trim()); Installer=$(($installOutput | Out-String).Trim()); SystemInventory=$(($inventoryOutput | Out-String).Trim())"
    exit 0
}
finally {
    Remove-Item -LiteralPath $corePath -Force -ErrorAction SilentlyContinue
}
