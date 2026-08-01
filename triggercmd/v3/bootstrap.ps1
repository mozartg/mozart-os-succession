[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$userRoot      = "C:\Users\mozar"
$scriptRoot    = Join-Path $userRoot "TriggerCMD-Scripts"
$controlRoot   = Join-Path $scriptRoot "Control"
$backupRoot    = Join-Path $controlRoot "Backups"
$receiptRoot   = Join-Path $controlRoot "Receipts\OneTime"
$triggerData   = Join-Path $userRoot ".TRIGGERcmdData"
$commandsPath  = Join-Path $triggerData "commands.json"
$sendResult    = Join-Path $triggerData "sendresult.bat"
$catdeskStart  = Join-Path $controlRoot "catdesk-autostart.ps1"
$catdeskState  = Join-Path $scriptRoot "Autonomy\catdesk-autostart-status.json"
$manifestUrl   = "https://raw.githubusercontent.com/mozartg/mozart-os-succession/main/triggercmd/v3/manifest.json"
$stamp         = Get-Date -Format "yyyyMMdd-HHmmss"

New-Item -ItemType Directory -Force -Path $scriptRoot,$controlRoot,$backupRoot,$receiptRoot | Out-Null

function Send-Now {
    param([Parameter(Mandatory)][string]$Text)
    $clean = ($Text -replace "`r?`n"," | ").Trim()
    if ($clean.Length -gt 850) { $clean = $clean.Substring(0,850) }
    if (Test-Path -LiteralPath $sendResult -PathType Leaf) {
        & $sendResult $clean | Out-Null
    }
}

function Normalize-Commands {
    param([Parameter(Mandatory)]$Parsed)
    if ($Parsed -is [Array]) { return @($Parsed) }
    if ($Parsed.PSObject.Properties.Name -contains "commands") { return @($Parsed.commands) }
    if ($Parsed.PSObject.Properties.Name -contains "trigger") { return @($Parsed) }
    throw "Unsupported commands.json structure."
}

function Assert-UnderRoot {
    param([string]$Path,[string]$Root)
    $full = [IO.Path]::GetFullPath($Path)
    $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd("\") + "\"
    if (-not $full.StartsWith($rootFull,[StringComparison]::OrdinalIgnoreCase)) {
        throw "Target outside script root: $full"
    }
}

function Write-Utf8NoBom {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Content)
    New-Item -ItemType Directory -Force -Path (Split-Path $Path -Parent) | Out-Null
    [IO.File]::WriteAllText($Path,$Content,[Text.UTF8Encoding]::new($false))
}

function Invoke-OneTimeActions {
    param([Parameter(Mandatory)]$Manifest)

    if (-not ($Manifest.PSObject.Properties.Name -contains "oneTimeActions")) {
        return @()
    }

    $actions = @($Manifest.oneTimeActions)
    if ($actions.Count -eq 0) { return @() }

    $tasksModule = Join-Path $controlRoot "tasks.psm1"
    if (-not (Test-Path -LiteralPath $tasksModule -PathType Leaf)) {
        throw "One-time actions requested but tasks module is missing."
    }

    Import-Module $tasksModule -Force -ErrorAction Stop
    $summaries = @()

    foreach ($action in $actions) {
        $id = [string]$action.id
        $task = [string]$action.task
        $inputText = if ($action.PSObject.Properties.Name -contains "input") { [string]$action.input } else { "" }

        if ($id -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{2,95}$') { throw "Invalid one-time action id: $id" }
        if ([string]::IsNullOrWhiteSpace($task)) { throw "One-time action task is empty: $id" }

        $successPath = Join-Path $receiptRoot "$id.json"
        if (Test-Path -LiteralPath $successPath -PathType Leaf) {
            $prior = Get-Content -LiteralPath $successPath -Raw | ConvertFrom-Json
            if ([string]$prior.status -eq "VERIFIED_COMPLETE") {
                $summaries += "Action=$id:already-complete"
                continue
            }
        }

        $started = (Get-Date).ToUniversalTime().ToString("o")
        try {
            $result = Invoke-ControlTask -Task $task -InputText $inputText
            $completed = (Get-Date).ToUniversalTime().ToString("o")
            $receipt = [ordered]@{
                schema = "control-plane-one-time-action/v1"
                action_id = $id
                task = $task
                input = $inputText
                status = "VERIFIED_COMPLETE"
                started_at = $started
                completed_at = $completed
                result = [string]$result
                control_plane_version = [string]$Manifest.version
            }
            $json = $receipt | ConvertTo-Json -Depth 20
            Write-Utf8NoBom -Path $successPath -Content $json
            $digest = (Get-FileHash -LiteralPath $successPath -Algorithm SHA256).Hash.ToLowerInvariant()
            Write-Utf8NoBom -Path ($successPath + ".sha256") -Content "$digest  $([IO.Path]::GetFileName($successPath))`n"
            $summaries += "Action=$id:complete:$result"
        }
        catch {
            $completed = (Get-Date).ToUniversalTime().ToString("o")
            $failurePath = Join-Path $receiptRoot ("{0}.failed-{1}.json" -f $id,(Get-Date -Format "yyyyMMdd-HHmmss"))
            $failure = [ordered]@{
                schema = "control-plane-one-time-action/v1"
                action_id = $id
                task = $task
                input = $inputText
                status = "FAILED"
                started_at = $started
                completed_at = $completed
                error = $_.Exception.Message
                control_plane_version = [string]$Manifest.version
            }
            Write-Utf8NoBom -Path $failurePath -Content ($failure | ConvertTo-Json -Depth 20)
            throw "One-time action $id failed: $($_.Exception.Message)"
        }
    }

    return $summaries
}

try {
    $manifestTemp = Join-Path $env:TEMP "triggercmd-manifest-$stamp.json"
    Invoke-WebRequest -Uri ($manifestUrl + "?t=" + [uri]::EscapeDataString($stamp)) -OutFile $manifestTemp -UseBasicParsing
    $manifest = Get-Content -LiteralPath $manifestTemp -Raw | ConvertFrom-Json

    $versionBackup = Join-Path $backupRoot $stamp
    New-Item -ItemType Directory -Force -Path $versionBackup | Out-Null

    foreach ($file in $manifest.files) {
        $target = Join-Path $scriptRoot ([string]$file.target)
        Assert-UnderRoot -Path $target -Root $scriptRoot
        New-Item -ItemType Directory -Force -Path (Split-Path $target -Parent) | Out-Null

        $download = "$target.download-$stamp"
        Invoke-WebRequest -Uri (([string]$file.url) + "?v=" + [uri]::EscapeDataString([string]$manifest.version)) -OutFile $download -UseBasicParsing

        $actual = (Get-FileHash -LiteralPath $download -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actual -ne ([string]$file.sha256).ToLowerInvariant()) {
            Remove-Item -LiteralPath $download -Force -ErrorAction SilentlyContinue
            throw "Hash mismatch for $($file.target)."
        }

        if ([IO.Path]::GetExtension($target) -match '(?i)^\.(ps1|psm1)$') {
            $tokens = $null
            $errors = $null
            [System.Management.Automation.Language.Parser]::ParseFile($download,[ref]$tokens,[ref]$errors) | Out-Null
            if ($errors.Count -gt 0) { throw "Syntax validation failed for $($file.target): $($errors[0].Message)" }
        }

        if (Test-Path -LiteralPath $target -PathType Leaf) {
            $relativeSafe = ([string]$file.target) -replace '[\\/:*?"<>|]','_'
            Copy-Item -LiteralPath $target -Destination (Join-Path $versionBackup $relativeSafe) -Force
        }

        Move-Item -LiteralPath $download -Destination $target -Force
    }

    Copy-Item -LiteralPath $commandsPath -Destination (Join-Path $versionBackup "commands.json") -Force
    $parsed = Get-Content -LiteralPath $commandsPath -Raw | ConvertFrom-Json
    $commands = @(Normalize-Commands -Parsed $parsed)

    $managed = @("bootstrap") + @($manifest.commands | ForEach-Object { [string]$_.trigger })
    $kept = @($commands | Where-Object {
        $null -ne $_ -and
        $_.PSObject.Properties.Name -contains "trigger" -and
        [string]$_.trigger -notin $managed
    })

    $final = @($kept)
    $final += [pscustomobject][ordered]@{
        trigger="bootstrap"
        command='powershell.exe -NoProfile -NonInteractive -ExecutionPolicy RemoteSigned -File C:\Users\mozar\TriggerCMD-Scripts\bootstrap.ps1'
        offCommand=""
        ground="foreground"
        voice=""
        voiceReply="{{result}}"
        allowParams="false"
    }

    foreach ($definition in $manifest.commands) {
        $commandText = 'powershell.exe -NoProfile -NonInteractive -ExecutionPolicy RemoteSigned -File C:\Users\mozar\TriggerCMD-Scripts\Control\fleet.ps1 -Task ' + [string]$definition.task
        if ([bool]$definition.allowParams) { $commandText += ' -Input' }

        $final += [pscustomobject][ordered]@{
            trigger=[string]$definition.trigger
            command=$commandText
            offCommand=""
            ground="foreground"
            voice=""
            voiceReply="{{result}}"
            allowParams=$(if ([bool]$definition.allowParams) { "true" } else { "false" })
        }
    }

    $tempCommands = "$commandsPath.tmp-$stamp"
    [IO.File]::WriteAllText($tempCommands,(ConvertTo-Json -InputObject ([object[]]$final) -Depth 20),[Text.UTF8Encoding]::new($false))
    $validated = @(Normalize-Commands -Parsed (Get-Content -LiteralPath $tempCommands -Raw | ConvertFrom-Json))

    foreach ($name in $managed) {
        $count = @($validated | Where-Object {
            $_.PSObject.Properties.Name -contains "trigger" -and [string]$_.trigger -eq $name
        }).Count
        if ($count -ne 1) { throw "Command validation failed for $name." }
    }

    Move-Item -LiteralPath $tempCommands -Destination $commandsPath -Force
    [IO.File]::WriteAllText((Join-Path $controlRoot "installed-version.json"),($manifest | ConvertTo-Json -Depth 20),[Text.UTF8Encoding]::new($false))

    $actionSummaries = @(Invoke-OneTimeActions -Manifest $manifest)

    $catdeskSummary = "not-run"
    if (Test-Path -LiteralPath $catdeskState -PathType Leaf) {
        try {
            $catState = Get-Content -LiteralPath $catdeskState -Raw | ConvertFrom-Json
            $catdeskSummary = "Online=$($catState.online) Phase=$($catState.phase) URL=$($catState.connectorUrl) Error=$($catState.error)"
        } catch {
            $catdeskSummary = "status-unreadable"
        }
    }

    $actionText = if ($actionSummaries.Count -gt 0) { " | " + ($actionSummaries -join " | ") } else { "" }
    Send-Now "CATDESK :: $catdeskSummary | ControlPlane=$($manifest.version) Commands=$($managed.Count)$actionText"

    if (Test-Path -LiteralPath $catdeskStart -PathType Leaf) {
        Start-Process powershell.exe -WindowStyle Hidden -ArgumentList @(
            "-NoProfile","-ExecutionPolicy","Bypass","-File",$catdeskStart
        )
    }

    $agentExe = Get-ChildItem -LiteralPath (Join-Path $env:LOCALAPPDATA "TRIGGERcmdAgent") -Filter "TRIGGERcmdAgent.exe" -File -Recurse |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
    $code = "Start-Sleep 3; Get-Process TRIGGERcmdAgent -ErrorAction SilentlyContinue | Stop-Process -Force; Start-Sleep 2; Start-Process '$agentExe'"
    Start-Process powershell.exe -WindowStyle Hidden -ArgumentList @("-NoProfile","-ExecutionPolicy","Bypass","-Command",$code)
    exit 0
}
catch {
    Send-Now "FAILED bootstrap :: $($_.Exception.Message)"
    exit 1
}
