Set-StrictMode -Version Latest

function Resolve-ControlPath {
    [CmdletBinding()]
    param(
        [string]$RelativePath,
        [switch]$RequireFile,
        [switch]$RequireDirectory
    )

    $userRoot = "C:\Users\mozar"
    if ([string]::IsNullOrWhiteSpace($RelativePath)) { $RelativePath = "." }

    $rootFull = [IO.Path]::GetFullPath($userRoot).TrimEnd("\")
    $candidate = if ([IO.Path]::IsPathRooted($RelativePath)) {
        [IO.Path]::GetFullPath($RelativePath)
    } else {
        [IO.Path]::GetFullPath((Join-Path $rootFull $RelativePath))
    }

    $inside = $candidate.Equals($rootFull,[StringComparison]::OrdinalIgnoreCase) -or
        $candidate.StartsWith($rootFull + "\",[StringComparison]::OrdinalIgnoreCase)

    if (-not $inside) { throw "Path outside C:\Users\mozar." }
    if ($RequireFile -and -not (Test-Path -LiteralPath $candidate -PathType Leaf)) { throw "File not found: $candidate" }
    if ($RequireDirectory -and -not (Test-Path -LiteralPath $candidate -PathType Container)) { throw "Directory not found: $candidate" }
    return $candidate
}

function Invoke-ControlTask {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Task,
        [string]$InputText
    )

    $userRoot = "C:\Users\mozar"

    switch ($Task) {
        "workspace_list" {
            $target = Resolve-ControlPath -RelativePath $InputText -RequireDirectory
            $items = @(Get-ChildItem -LiteralPath $target -Force -ErrorAction Stop | Sort-Object Name | Select-Object -First 80)
            return "Path=$target; Items=$($items.Count); " + (($items | ForEach-Object {
                "{0}:{1}:{2}" -f ($(if ($_.PSIsContainer) { "DIR" } else { "FILE" }),$_.Name,$_.Length)
            }) -join " || ")
        }

        "workspace_read" {
            $target = Resolve-ControlPath -RelativePath $InputText -RequireFile
            if ($target -match '(?i)\\(\.ssh|\.gnupg)\\') { throw "Sensitive directory blocked." }
            if ([IO.Path]::GetExtension($target) -match '(?i)^\.(pem|key|pfx|p12|kdbx|sqlite|db)$') { throw "Sensitive or binary file type blocked." }

            $info = Get-Item -LiteralPath $target
            if ($info.Length -gt 1048576) { throw "File exceeds 1 MB." }

            $raw = Get-Content -LiteralPath $target -Raw -ErrorAction Stop
            $safe = $raw -replace '(?im)^.*(?:password|passwd|secret|token|authtoken|api[_-]?key|private[_-]?key)\s*[:=].*$','[REDACTED]'
            if ($safe.Length -gt 3000) { $safe = $safe.Substring(0,3000) }
            return "File=$target; Bytes=$($info.Length); Preview=$safe"
        }

        "system_health" {
            $os = Get-CimInstance Win32_OperatingSystem
            $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
            return "OS=$($os.Caption) $($os.Version); RAMFreeGB=$([math]::Round($os.FreePhysicalMemory/1MB,2)); CFreeGB=$([math]::Round($disk.FreeSpace/1GB,2)); UptimeHours=$([math]::Round(((Get-Date)-$os.LastBootUpTime).TotalHours,1))"
        }

        "process_find" {
            if ([string]::IsNullOrWhiteSpace($InputText)) { throw "Supply a process-name fragment." }
            $rows = @(Get-CimInstance Win32_Process | Where-Object {
                $_.Name -like "*$InputText*" -or $_.CommandLine -like "*$InputText*"
            } | Select-Object -First 30)
            return "Matches=$($rows.Count); " + (($rows | ForEach-Object {
                "$($_.Name):PID=$($_.ProcessId):$($_.ExecutablePath)"
            }) -join " || ")
        }

        "port_check" {
            $port = 0
            if (-not [int]::TryParse($InputText,[ref]$port) -or $port -lt 1 -or $port -gt 65535) { throw "Supply a TCP port from 1 to 65535." }
            $rows = @(Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue)
            return "Port=$port; Count=$($rows.Count); " + (($rows | ForEach-Object {
                "$($_.LocalAddress):$($_.LocalPort):$($_.State):PID=$($_.OwningProcess)"
            }) -join " || ")
        }

        "command_find" {
            if ([string]::IsNullOrWhiteSpace($InputText)) { throw "Supply a command name." }
            $rows = @(Get-Command $InputText -All -ErrorAction SilentlyContinue | Select-Object -First 20)
            return "Matches=$($rows.Count); " + (($rows | ForEach-Object {
                "$($_.Name):$($_.CommandType):$($_.Source)"
            }) -join " || ")
        }

        "catdesk_status" {
            $rows = @(Get-CimInstance Win32_Process | Where-Object {
                $_.Name -ieq "catdesk.exe" -or
                ($_.Name -ieq "node.exe" -and $_.CommandLine -match "(?i)catdesk") -or
                $_.Name -ieq "ngrok.exe"
            })
            $listen = @(Get-NetTCPConnection -LocalPort 3200 -State Listen -ErrorAction SilentlyContinue)
            return "Processes=$($rows.Count); PIDs=$(($rows.ProcessId -join ',')); Port3200=$($listen.Count -gt 0); Config=$(Test-Path -LiteralPath 'C:\Users\mozar\.catdesk\config.toml')"
        }

        "playwright_status" {
            $browserRoot = Join-Path $env:LOCALAPPDATA "ms-playwright"
            $browsers = @(Get-ChildItem -LiteralPath $browserRoot -Directory -ErrorAction SilentlyContinue)
            return "Node=$([bool](Get-Command node.exe -ErrorAction SilentlyContinue)); Npm=$([bool](Get-Command npm.cmd -ErrorAction SilentlyContinue)); Npx=$([bool](Get-Command npx.cmd -ErrorAction SilentlyContinue)); BrowserPackages=$(($browsers.Name -join ','))"
        }

        "browser_status" {
            $candidates = @(
                "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
                "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
                "$env:LOCALAPPDATA\Microsoft\Edge\Application\msedge.exe",
                "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
                "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
                "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
            )
            $found = @($candidates | Where-Object { Test-Path -LiteralPath $_ })
            $debug = @(Get-NetTCPConnection -LocalPort 9222 -State Listen -ErrorAction SilentlyContinue)
            return "Browsers=$(($found -join ' | ')); Debug9222=$($debug.Count -gt 0)"
        }

        "approved_inventory" {
            $folder = Join-Path $userRoot "TriggerCMD-Scripts\Approved"
            $items = @(Get-ChildItem -LiteralPath $folder -File -Force -ErrorAction SilentlyContinue | Sort-Object Name | Select-Object -First 80)
            return "Folder=$folder; Files=$($items.Count); " + (($items | ForEach-Object {
                "$($_.Name):$($_.Length):$($_.LastWriteTime)"
            }) -join " || ")
        }

        default { throw "Unknown task: $Task" }
    }
}

Export-ModuleMember -Function Resolve-ControlPath,Invoke-ControlTask
