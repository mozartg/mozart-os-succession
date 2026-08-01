[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$userRoot     = "C:\Users\mozar"
$triggerData  = Join-Path $userRoot ".TRIGGERcmdData"
$scriptRoot   = Join-Path $userRoot "TriggerCMD-Scripts"
$fleetRoot    = Join-Path $scriptRoot "Fleet"
$logsRoot     = Join-Path $scriptRoot "Logs"
$commandsPath = Join-Path $triggerData "commands.json"
$fleetPath    = Join-Path $fleetRoot "fleet.ps1"
$sendResult   = Join-Path $triggerData "sendresult.bat"
$stamp        = Get-Date -Format "yyyyMMdd-HHmmss"
$logPath      = Join-Path $logsRoot "bootstrap-v2-$stamp.log"
$backupPath   = "$commandsPath.before-fleet-$stamp"

New-Item -ItemType Directory -Path $fleetRoot -Force | Out-Null
New-Item -ItemType Directory -Path $logsRoot -Force | Out-Null

function Write-BootstrapLog {
    param([Parameter(Mandatory)][string]$Message)
    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    $line | Tee-Object -FilePath $logPath -Append
}

function Send-BootstrapResult {
    param(
        [Parameter(Mandatory)][string]$Status,
        [Parameter(Mandatory)][string]$Text
    )

    $clean = ($Text -replace "`r?`n", " | ").Trim()
    if ($clean.Length -gt 820) {
        $clean = $clean.Substring(0, 820)
    }

    $message = "$Status bootstrap :: $clean"
    Write-BootstrapLog $message

    if (Test-Path -LiteralPath $sendResult -PathType Leaf) {
        & $sendResult $message | Out-Null
    }
}

function Normalize-Commands {
    param([Parameter(Mandatory)]$Parsed)

    if ($Parsed -is [Array]) {
        return @($Parsed)
    }

    if ($Parsed.PSObject.Properties.Name -contains "commands") {
        return @($Parsed.commands)
    }

    if ($Parsed.PSObject.Properties.Name -contains "trigger") {
        return @($Parsed)
    }

    throw "Unsupported commands.json structure."
}

function New-Command {
    param(
        [Parameter(Mandatory)][string]$Trigger,
        [Parameter(Mandatory)][string]$Task,
        [bool]$AllowParams = $false
    )

    $commandText = 'powershell.exe -NoProfile -NonInteractive -ExecutionPolicy RemoteSigned -File "' +
        $fleetPath + '" -Task ' + $Task

    if ($AllowParams) {
        $commandText += ' -Input'
    }

    return [pscustomobject][ordered]@{
        trigger     = $Trigger
        command     = $commandText
        offCommand  = ""
        ground      = "foreground"
        voice       = ""
        voiceReply  = "{{result}}"
        allowParams = $(if ($AllowParams) { "true" } else { "false" })
    }
}

try {
    Write-BootstrapLog "Bootstrap v2 started."

    if (-not (Test-Path -LiteralPath $commandsPath -PathType Leaf)) {
        throw "commands.json is missing."
    }

    Copy-Item -LiteralPath $commandsPath -Destination $backupPath -Force
    Write-BootstrapLog "Backup created: $backupPath"

    $fleetContent = @'
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet(
        "fleet_status",
        "trigger_status",
        "trigger_logs",
        "workspace_list",
        "workspace_read",
        "system_health",
        "process_find",
        "port_check",
        "command_find",
        "catdesk_status",
        "playwright_status",
        "browser_status",
        "approved_inventory",
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
$scriptRoot   = Join-Path $userRoot "TriggerCMD-Scripts"
$logsRoot     = Join-Path $scriptRoot "Logs"
$commandsPath = Join-Path $triggerData "commands.json"
$sendResult   = Join-Path $triggerData "sendresult.bat"
$stamp        = Get-Date -Format "yyyyMMdd-HHmmssfff"
$logPath      = Join-Path $logsRoot "fleet-$Task-$stamp.log"

New-Item -ItemType Directory -Path $logsRoot -Force | Out-Null

function Write-FleetLog {
    param([Parameter(Mandatory)][string]$Message)
    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    $line | Out-File -LiteralPath $logPath -Append -Encoding utf8
}

function Send-FleetResult {
    param(
        [Parameter(Mandatory)][string]$Status,
        [Parameter(Mandatory)][string]$Text
    )

    $clean = ($Text -replace "`r?`n", " | ").Trim()
    if ($clean.Length -gt 820) {
        $clean = $clean.Substring(0, 820)
    }

    $message = "$Status $Task :: $clean"
    Write-FleetLog $message

    if (Test-Path -LiteralPath $sendResult -PathType Leaf) {
        & $sendResult $message | Out-Null
    }
}

function Resolve-UserPath {
    param(
        [string]$RelativePath,
        [switch]$RequireFile,
        [switch]$RequireDirectory
    )

    if ([string]::IsNullOrWhiteSpace($RelativePath)) {
        $RelativePath = "."
    }

    $rootFull = [IO.Path]::GetFullPath($userRoot).TrimEnd("\")
    $rootPrefix = $rootFull + "\"

    if ([IO.Path]::IsPathRooted($RelativePath)) {
        $candidate = [IO.Path]::GetFullPath($RelativePath)
    } else {
        $candidate = [IO.Path]::GetFullPath((Join-Path $userRoot $RelativePath))
    }

    $insideRoot = $candidate.Equals(
        $rootFull,
        [StringComparison]::OrdinalIgnoreCase
    ) -or $candidate.StartsWith(
        $rootPrefix,
        [StringComparison]::OrdinalIgnoreCase
    )

    if (-not $insideRoot) {
        throw "Path is outside C:\Users\mozar."
    }

    if ($RequireFile -and -not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
        throw "File not found: $candidate"
    }

    if ($RequireDirectory -and -not (Test-Path -LiteralPath $candidate -PathType Container)) {
        throw "Directory not found: $candidate"
    }

    return $candidate
}

function Redact-Text {
    param([Parameter(Mandatory)][string]$Text)

    $patterns = @(
        '(?im)^.*(?:password|passwd|secret|token|authtoken|api[_-]?key|private[_-]?key|mcpSlug)\s*[:=].*$',
        '(?i)ghp_[A-Za-z0-9]{20,}',
        '(?i)github_pat_[A-Za-z0-9_]{20,}',
        '(?i)sk-[A-Za-z0-9_-]{20,}',
        '(?i)xox[baprs]-[A-Za-z0-9-]{10,}',
        '(?i)AIza[A-Za-z0-9_-]{20,}'
    )

    $redacted = $Text
    foreach ($pattern in $patterns) {
        $redacted = [regex]::Replace($redacted, $pattern, "[REDACTED]")
    }
    return $redacted
}

try {
    $joinedInput = (($Input | Where-Object { $null -ne $_ }) -join " ").Trim()
    Write-FleetLog "Task=$Task Input=$joinedInput"

    switch ($Task) {
        "fleet_status" {
            $parsed = Get-Content -LiteralPath $commandsPath -Raw | ConvertFrom-Json
            if ($parsed -is [Array]) {
                $commands = @($parsed)
            } elseif ($parsed.PSObject.Properties.Name -contains "commands") {
                $commands = @($parsed.commands)
            } else {
                $commands = @($parsed)
            }

            $names = @(
                $commands |
                Where-Object {
                    $null -ne $_ -and
                    $_.PSObject.Properties.Name -contains "trigger"
                } |
                ForEach-Object { [string]$_.trigger } |
                Sort-Object
            )

            $agent = Get-CimInstance Win32_Process |
                Where-Object {
                    $_.Name -ieq "TRIGGERcmdAgent.exe" -and
                    $_.CommandLine -notmatch "--type="
                } |
                Select-Object -First 1

            $text = "AgentRunning=$($null -ne $agent); CommandCount=$($names.Count); Commands=$($names -join ', '); Log=$logPath"
            Send-FleetResult -Status "OK" -Text $text
        }

        "trigger_status" {
            $agentProcesses = @(
                Get-CimInstance Win32_Process |
                Where-Object { $_.Name -ieq "TRIGGERcmdAgent.exe" }
            )

            $main = $agentProcesses |
                Where-Object { $_.CommandLine -notmatch "--type=" } |
                Select-Object -First 1

            $text = "MainAgent=$($null -ne $main); MainPID=$(if ($main) { $main.ProcessId } else { 'none' }); TotalAgentProcesses=$($agentProcesses.Count); CommandsFile=$(Test-Path -LiteralPath $commandsPath)"
            Send-FleetResult -Status "OK" -Text $text
        }

        "trigger_logs" {
            $logs = @(
                Get-ChildItem -LiteralPath $triggerData -File -Recurse -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.Extension -in ".log", ".txt" -or
                    $_.Name -match "(?i)debug|trigger|bootstrap|fleet"
                } |
                Sort-Object LastWriteTime -Descending
            )

            $latest = $logs | Select-Object -First 1
            if (-not $latest) {
                $text = "No TRIGGERcmd log was found."
            } else {
                $tail = (Get-Content -LiteralPath $latest.FullName -Tail 12 -ErrorAction Stop) -join " | "
                $text = "File=$($latest.FullName); Modified=$($latest.LastWriteTime); Tail=$tail"
            }
            Send-FleetResult -Status "OK" -Text $text
        }

        "workspace_list" {
            $target = Resolve-UserPath -RelativePath $joinedInput -RequireDirectory
            $items = @(
                Get-ChildItem -LiteralPath $target -Force -ErrorAction Stop |
                Sort-Object @{ Expression = { -not $_.PSIsContainer } }, Name |
                Select-Object -First 40
            )

            $lines = foreach ($item in $items) {
                $kind = if ($item.PSIsContainer) { "DIR" } else { "FILE" }
                "$kind`t$($item.Name)`t$($item.Length)`t$($item.LastWriteTime)"
            }

            $text = "Path=$target; Items=$($items.Count); " + ($lines -join " || ")
            Send-FleetResult -Status "OK" -Text $text
        }

        "workspace_read" {
            $target = Resolve-UserPath -RelativePath $joinedInput -RequireFile

            $blocked = @(
                "\.ssh\",
                "\.gnupg\",
                "\AppData\Local\Google\Chrome\User Data\",
                "\AppData\Local\Microsoft\Edge\User Data\"
            )

            foreach ($fragment in $blocked) {
                if ($target.IndexOf($fragment, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
                    throw "Reading this sensitive location is blocked."
                }
            }

            if ([IO.Path]::GetExtension($target) -match '(?i)^\.(pem|key|pfx|p12|kdbx|sqlite|db)$') {
                throw "Reading this sensitive or binary file type is blocked."
            }

            $info = Get-Item -LiteralPath $target
            if ($info.Length -gt 1048576) {
                throw "File exceeds the 1 MB read limit."
            }

            $raw = Get-Content -LiteralPath $target -Raw -ErrorAction Stop
            $safe = Redact-Text -Text $raw
            $preview = if ($safe.Length -gt 720) { $safe.Substring(0, 720) } else { $safe }
            $text = "File=$target; Bytes=$($info.Length); Preview=$preview"
            Send-FleetResult -Status "OK" -Text $text
        }

        "system_health" {
            $os = Get-CimInstance Win32_OperatingSystem
            $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
            $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
            $memTotalGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
            $memFreeGB = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
            $diskFreeGB = [math]::Round($disk.FreeSpace / 1GB, 2)
            $diskTotalGB = [math]::Round($disk.Size / 1GB, 2)
            $uptime = (Get-Date) - $os.LastBootUpTime

            $text = "OS=$($os.Caption) $($os.Version); CPU=$($cpu.Name); RAM_FreeGB=$memFreeGB/$memTotalGB; C_FreeGB=$diskFreeGB/$diskTotalGB; UptimeHours=$([math]::Round($uptime.TotalHours,1))"
            Send-FleetResult -Status "OK" -Text $text
        }

        "process_find" {
            if ([string]::IsNullOrWhiteSpace($joinedInput)) {
                throw "Supply a process-name fragment."
            }

            $matches = @(
                Get-CimInstance Win32_Process |
                Where-Object {
                    $_.Name -like "*$joinedInput*" -or
                    $_.CommandLine -like "*$joinedInput*"
                } |
                Select-Object -First 20
            )

            $lines = foreach ($process in $matches) {
                "$($process.Name):PID=$($process.ProcessId):$($process.ExecutablePath)"
            }

            $text = "Query=$joinedInput; Matches=$($matches.Count); " + ($lines -join " || ")
            Send-FleetResult -Status "OK" -Text $text
        }

        "port_check" {
            $port = 0
            if (-not [int]::TryParse($joinedInput, [ref]$port) -or $port -lt 1 -or $port -gt 65535) {
                throw "Supply one numeric TCP port from 1 to 65535."
            }

            $connections = @(
                Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue
            )

            $lines = foreach ($connection in $connections | Select-Object -First 20) {
                "$($connection.LocalAddress):$($connection.LocalPort):$($connection.State):PID=$($connection.OwningProcess)"
            }

            $text = "Port=$port; Connections=$($connections.Count); " + ($lines -join " || ")
            Send-FleetResult -Status "OK" -Text $text
        }

        "command_find" {
            if ([string]::IsNullOrWhiteSpace($joinedInput)) {
                throw "Supply a command name."
            }

            $commands = @(
                Get-Command $joinedInput -All -ErrorAction SilentlyContinue |
                Select-Object -First 10
            )

            $lines = foreach ($command in $commands) {
                "$($command.Name):$($command.CommandType):$($command.Source)"
            }

            $text = "Query=$joinedInput; Matches=$($commands.Count); " + ($lines -join " || ")
            Send-FleetResult -Status "OK" -Text $text
        }

        "catdesk_status" {
            $processes = @(
                Get-CimInstance Win32_Process |
                Where-Object {
                    $_.Name -ieq "catdesk.exe" -or
                    ($_.Name -ieq "node.exe" -and $_.CommandLine -match "(?i)catdesk") -or
                    $_.Name -ieq "ngrok.exe"
                }
            )

            $port3200 = @(
                Get-NetTCPConnection -LocalPort 3200 -State Listen -ErrorAction SilentlyContinue
            )

            $config = Join-Path $userRoot ".catdesk\config.toml"
            $text = "Processes=$($processes.Count); PIDs=$(($processes.ProcessId -join ',')); Port3200Listening=$($port3200.Count -gt 0); ConfigExists=$(Test-Path -LiteralPath $config)"
            Send-FleetResult -Status "OK" -Text $text
        }

        "playwright_status" {
            $node = Get-Command node.exe -ErrorAction SilentlyContinue
            $npm = Get-Command npm.cmd -ErrorAction SilentlyContinue
            $npx = Get-Command npx.cmd -ErrorAction SilentlyContinue
            $browserRoot = Join-Path $env:LOCALAPPDATA "ms-playwright"
            $browsers = @(
                Get-ChildItem -LiteralPath $browserRoot -Directory -ErrorAction SilentlyContinue
            )

            $text = "Node=$($null -ne $node); Npm=$($null -ne $npm); Npx=$($null -ne $npx); BrowserRoot=$browserRoot; BrowserPackages=$(($browsers.Name -join ','))"
            Send-FleetResult -Status "OK" -Text $text
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
            $port9222 = @(
                Get-NetTCPConnection -LocalPort 9222 -State Listen -ErrorAction SilentlyContinue
            )

            $text = "Browsers=$(($found -join ' | ')); DebugPort9222=$($port9222.Count -gt 0)"
            Send-FleetResult -Status "OK" -Text $text
        }

        "approved_inventory" {
            $approved = Join-Path $scriptRoot "Approved"
            $items = @(
                Get-ChildItem -LiteralPath $approved -File -Force -ErrorAction SilentlyContinue |
                Sort-Object Name |
                Select-Object -First 40
            )

            $lines = foreach ($item in $items) {
                "$($item.Name):$($item.Length):$($item.LastWriteTime)"
            }

            $text = "Folder=$approved; Files=$($items.Count); " + ($lines -join " || ")
            Send-FleetResult -Status "OK" -Text $text
        }

        "trigger_reload" {
            $agentExe = @(
                Join-Path $env:LOCALAPPDATA "TRIGGERcmdAgent\TRIGGERcmdAgent.exe"
                Get-ChildItem -LiteralPath (Join-Path $env:LOCALAPPDATA "TRIGGERcmdAgent") `
                    -Filter "TRIGGERcmdAgent.exe" `
                    -File `
                    -Recurse `
                    -ErrorAction SilentlyContinue |
                    Sort-Object LastWriteTime -Descending |
                    Select-Object -ExpandProperty FullName
            ) |
            Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } |
            Select-Object -First 1

            if (-not $agentExe) {
                throw "TRIGGERcmdAgent.exe was not found."
            }

            Send-FleetResult -Status "OK" -Text "Agent restart scheduled; Executable=$agentExe"

            $restartCode = @"
Start-Sleep -Seconds 3
Get-Process -Name 'TRIGGERcmdAgent' -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2
Start-Process -FilePath '$agentExe'
"@

            $encoded = [Convert]::ToBase64String(
                [Text.Encoding]::Unicode.GetBytes($restartCode)
            )

            Start-Process powershell.exe `
                -WindowStyle Hidden `
                -ArgumentList @(
                    "-NoProfile",
                    "-ExecutionPolicy", "Bypass",
                    "-EncodedCommand", $encoded
                )

            exit 0
        }
    }

    exit 0
}
catch {
    $message = $_.Exception.Message
    Send-FleetResult -Status "FAILED" -Text $message
    Write-Error $_
    exit 1
}
'@

    [IO.File]::WriteAllText(
        $fleetPath,
        $fleetContent,
        [Text.UTF8Encoding]::new($false)
    )
    Write-BootstrapLog "Fleet dispatcher written: $fleetPath"

    $parsed = Get-Content -LiteralPath $commandsPath -Raw | ConvertFrom-Json
    $commands = @(Normalize-Commands -Parsed $parsed)

    $fleetDefinitions = @(
        [pscustomobject]@{ Trigger = "fleet_status";       Task = "fleet_status";       AllowParams = $false },
        [pscustomobject]@{ Trigger = "trigger_status";     Task = "trigger_status";     AllowParams = $false },
        [pscustomobject]@{ Trigger = "trigger_logs";       Task = "trigger_logs";       AllowParams = $false },
        [pscustomobject]@{ Trigger = "workspace_list";     Task = "workspace_list";     AllowParams = $true  },
        [pscustomobject]@{ Trigger = "workspace_read";     Task = "workspace_read";     AllowParams = $true  },
        [pscustomobject]@{ Trigger = "system_health";      Task = "system_health";      AllowParams = $false },
        [pscustomobject]@{ Trigger = "process_find";       Task = "process_find";       AllowParams = $true  },
        [pscustomobject]@{ Trigger = "port_check";         Task = "port_check";         AllowParams = $true  },
        [pscustomobject]@{ Trigger = "command_find";       Task = "command_find";       AllowParams = $true  },
        [pscustomobject]@{ Trigger = "catdesk_status";     Task = "catdesk_status";     AllowParams = $false },
        [pscustomobject]@{ Trigger = "playwright_status";  Task = "playwright_status";  AllowParams = $false },
        [pscustomobject]@{ Trigger = "browser_status";     Task = "browser_status";     AllowParams = $false },
        [pscustomobject]@{ Trigger = "approved_inventory"; Task = "approved_inventory"; AllowParams = $false },
        [pscustomobject]@{ Trigger = "trigger_reload";     Task = "trigger_reload";     AllowParams = $false }
    )

    $managedNames = @("bootstrap") + @($fleetDefinitions | ForEach-Object { $_.Trigger })
    $kept = @(
        $commands |
        Where-Object {
            $null -ne $_ -and
            $_.PSObject.Properties.Name -contains "trigger" -and
            [string]$_.trigger -notin $managedNames
        }
    )

    $bootstrapCommand = [pscustomobject][ordered]@{
        trigger     = "bootstrap"
        command     = 'powershell.exe -NoProfile -NonInteractive -ExecutionPolicy RemoteSigned -File "C:\Users\mozar\TriggerCMD-Scripts\bootstrap.ps1"'
        offCommand  = ""
        ground      = "foreground"
        voice       = ""
        voiceReply  = "{{result}}"
        allowParams = "false"
    }

    $finalCommands = @($kept)
    $finalCommands += $bootstrapCommand

    foreach ($definition in $fleetDefinitions) {
        $finalCommands += New-Command `
            -Trigger $definition.Trigger `
            -Task $definition.Task `
            -AllowParams ([bool]$definition.AllowParams)
    }

    $tempPath = "$commandsPath.tmp-$stamp"
    $json = ConvertTo-Json -InputObject ([object[]]$finalCommands) -Depth 20
    [IO.File]::WriteAllText(
        $tempPath,
        $json,
        [Text.UTF8Encoding]::new($false)
    )

    $validatedParsed = Get-Content -LiteralPath $tempPath -Raw | ConvertFrom-Json
    $validated = @(Normalize-Commands -Parsed $validatedParsed)

    foreach ($name in $managedNames) {
        $count = @(
            $validated |
            Where-Object {
                $null -ne $_ -and
                $_.PSObject.Properties.Name -contains "trigger" -and
                [string]$_.trigger -eq $name
            }
        ).Count

        if ($count -ne 1) {
            throw "Validation failed for '$name'; count=$count."
        }
    }

    Move-Item -LiteralPath $tempPath -Destination $commandsPath -Force
    Write-BootstrapLog "commands.json replaced atomically."

    Start-Sleep -Seconds 4

    $text = "Fleet installed; Commands=$($managedNames.Count); Backup=$backupPath; Fleet=$fleetPath; Log=$logPath"
    Send-BootstrapResult -Status "OK" -Text $text
    exit 0
}
catch {
    Send-BootstrapResult -Status "FAILED" -Text $_.Exception.Message
    Write-Error $_
    exit 1
}
