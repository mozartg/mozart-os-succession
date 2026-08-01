[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = 'C:\Users\mozar\MachineInventory'
$statusPath = Join-Path $root 'launch-status.json'
$installerPath = 'C:\Users\mozar\TriggerCMD-Scripts\Control\system-inventory-installer.ps1'
$collectorPath = 'C:\Users\mozar\TriggerCMD-Scripts\Control\system-inventory.ps1'
$installerUrl = 'https://raw.githubusercontent.com/mozartg/mozart-os-succession/bfefe54b99e217d90ca2b5336ec4d7d40f8096fd/triggercmd/v3/system-inventory-installer.ps1'
$utf8NoBom = [Text.UTF8Encoding]::new($false)

New-Item -ItemType Directory -Force -Path $root,(Split-Path $installerPath -Parent) | Out-Null

$status = [ordered]@{
  schema = 'catdesk-system-inventory-launch/v1'
  status = 'running'
  started_at = (Get-Date).ToUniversalTime().ToString('o')
  completed_at = $null
  installer_url = $installerUrl
  installer_path = $installerPath
  collector_path = $collectorPath
  inventory_path = (Join-Path $root 'system-inventory.json')
  inventory_sha256 = $null
  collector_output = $null
  error = $null
}

try {
  [IO.File]::WriteAllText($statusPath,($status | ConvertTo-Json -Depth 10),$utf8NoBom)
  Invoke-WebRequest -Uri ($installerUrl + '?t=' + [uri]::EscapeDataString((Get-Date).ToUniversalTime().ToString('yyyyMMddHHmmss'))) -OutFile $installerPath -UseBasicParsing
  & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy RemoteSigned -File $installerPath
  if ($LASTEXITCODE -ne 0) { throw "Inventory installer exited $LASTEXITCODE." }
  if (-not (Test-Path -LiteralPath $collectorPath -PathType Leaf)) { throw "Collector missing: $collectorPath" }

  $output = @(& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy RemoteSigned -File $collectorPath 2>&1)
  $code = $LASTEXITCODE
  $status.collector_output = (($output | Out-String).Trim())
  if ($code -ne 0) { throw "Inventory collector exited $code." }

  $inventoryPath = Join-Path $root 'system-inventory.json'
  if (-not (Test-Path -LiteralPath $inventoryPath -PathType Leaf)) { throw "Inventory JSON missing: $inventoryPath" }
  Get-Content -LiteralPath $inventoryPath -Raw | ConvertFrom-Json | Out-Null
  $status.inventory_sha256 = (Get-FileHash -LiteralPath $inventoryPath -Algorithm SHA256).Hash.ToLowerInvariant()
  $status.status = 'completed'
}
catch {
  $status.status = 'failed'
  $status.error = $_.Exception.Message
}
finally {
  $status.completed_at = (Get-Date).ToUniversalTime().ToString('o')
  [IO.File]::WriteAllText($statusPath,($status | ConvertTo-Json -Depth 10),$utf8NoBom)
}

if ($status.status -ne 'completed') { exit 1 }
