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

function Invoke-Checked {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$Arguments = @()
    )
    $output = @(& $FilePath @Arguments 2>&1)
    $code = $LASTEXITCODE
    $text = ($output | Out-String).Trim()
    if ($code -ne 0) {
        if ([string]::IsNullOrWhiteSpace($text)) { $text = "$FilePath exited $code." }
        throw $text
    }
    return $text
}

function Write-Utf8NoBom {
    param([string]$Path,[string]$Content)
    New-Item -ItemType Directory -Force -Path (Split-Path $Path -Parent) | Out-Null
    [IO.File]::WriteAllText($Path,$Content,[Text.UTF8Encoding]::new($false))
}

function Invoke-MediaFactoryBootstrap {
    $userRoot = "C:\Users\mozar"
    $repo = "mozartg/media-factory"
    $localRoot = Join-Path $userRoot "Documents\media-factory"
    $receiptRoot = Join-Path $userRoot "TriggerCMD-Scripts\Control\Receipts"
    New-Item -ItemType Directory -Force -Path $receiptRoot | Out-Null

    $gh = Get-Command gh.exe -ErrorAction SilentlyContinue
    if (-not $gh) { $gh = Get-Command gh -ErrorAction SilentlyContinue }
    if (-not $gh) { throw "GitHub CLI not found." }

    $auth = Invoke-Checked -FilePath $gh.Source -Arguments @("auth","status","--hostname","github.com")
    if ($auth -notmatch "(?i)Logged in to github.com account mozartg") {
        throw "GitHub CLI is not authenticated as mozartg."
    }

    $created = $false
    $existing = $true
    $metaText = @(& $gh.Source api "repos/$repo" 2>$null)
    if ($LASTEXITCODE -ne 0) {
        $existing = $false
        Invoke-Checked -FilePath $gh.Source -Arguments @(
            "repo","create",$repo,
            "--private",
            "--description","Canonical private Media Factory: benchmarks, adapters, workflows, tests, receipts, and consumer manifests.",
            "--add-readme"
        ) | Out-Null
        $created = $true
        Start-Sleep -Seconds 2
        $metaText = @(& $gh.Source api "repos/$repo" 2>&1)
        if ($LASTEXITCODE -ne 0) { throw (($metaText | Out-String).Trim()) }
    }

    $meta = (($metaText | Out-String).Trim()) | ConvertFrom-Json
    if (-not [bool]$meta.private -or [string]$meta.visibility -ne "private") {
        throw "Provider readback did not confirm a private repository."
    }

    if (Test-Path -LiteralPath $localRoot -PathType Container) {
        $origin = @(& git -C $localRoot remote get-url origin 2>$null)
        if ($LASTEXITCODE -ne 0 -or (($origin | Out-String) -notmatch "mozartg/media-factory")) {
            throw "Existing local media-factory directory is not the admitted repository."
        }
        & git -C $localRoot fetch origin --prune 2>&1 | Out-Null
    } else {
        New-Item -ItemType Directory -Force -Path (Split-Path $localRoot -Parent) | Out-Null
        Invoke-Checked -FilePath $gh.Source -Arguments @("repo","clone",$repo,$localRoot) | Out-Null
    }

    $readme = @'
# Media Factory

Private canonical implementation repository for media-generation benchmarks, adapters, workflows, canaries, QA, receipts, custody, and cross-repository consumer manifests.

## Non-negotiable boundaries

- `mgvisuals` is a failed DIY generator and migration source only. It has no governance authority.
- `mo-stack` and `mozart-os` are migration sources only.
- Recommendations for active projects are incomplete until integrated, invoked, canary-tested, independently verified, linked from consumers, and receipt-backed.
- A trigger acknowledgement, queue entry, generated file, commit, or technical check alone is not end-to-end completion.
- ChatGPT may establish a first visual direction, but scalable production must test and use admitted local and cloud adapters.
- The user-approved “Come As You Are / Saved You a Seat” visual is the initial cross-adapter benchmark.

## Repository map

- `authority/` — verification and implementation boundaries
- `benchmarks/` — approved masters and evaluation descriptions
- `adapters/` — image, audio, motion, video, composition, custody, and delivery integrations
- `contracts/` — adapter, job, consumer, evaluation, and receipt schemas
- `workflows/` — orchestration and retry definitions
- `tests/` — positive, negative, regression, and canary tests
- `receipts/` — immutable implementation and runtime evidence
- `consumers/` — portfolio-wide consumer registry
- `migration/` — source-level dispositions for legacy repositories
'@

    $verification = @'
# Verified-State Standard

Every material claim must be treated as `VERIFIED`, `INFERRED`, `UNVERIFIED`, or `CONTRADICTED`.

A completion claim requires:
1. exact target and operation;
2. invocation receipt;
3. provider or destination readback;
4. linked object, commit, run, artifact, or asset ID;
5. hashes when available;
6. independent technical verification;
7. independent creative or outcome verification where applicable;
8. explicit coverage limits and strongest contrary explanation;
9. a changed-method retry before declaring a capability unavailable.

After three failures against the same outcome in one day, change transport, provider, execution host, adapter, credential source, workflow, or verification method. Do not repeat the same broken route.
'@

    $benchmark = [ordered]@{
        schema = "media-factory-benchmark/v1"
        benchmark_id = "come-as-you-are-saved-you-a-seat-v1"
        status = "user_approved_master"
        approved_at = "2026-08-01"
        source = [ordered]@{
            conversation_file = "4865.png"
            sha256 = "pending_local_or_custody_binding"
            custody = "pending_cloudinary_and_repository_receipt"
        }
        exact_copy = [ordered]@{
            headline_line_1 = "COME AS"
            headline_line_2 = "YOU ARE"
            subheadline = "Media and websites that help people feel seen."
            footer = "Saved You a Seat"
        }
        required_character = @(
            "warm textured editorial poster",
            "human-centered Black creative consultation",
            "distressed condensed headline typography",
            "cream black warm-red and mustard palette",
            "realistic lower photographic scene",
            "cozy studio with website mockup and creative tools",
            "welcoming relational tone"
        )
        production_rule = "ChatGPT may establish an initial visual direction; scale testing must use admitted local and cloud adapters plus deterministic composition and exact-copy controls."
        acceptance = [ordered]@{
            minimum_each_applicable_score = 80
            three_distinct_canaries = $true
            technical_validity_alone_sufficient = $false
            exact_copy_required = $true
            independent_creative_review_required = $true
        }
    } | ConvertTo-Json -Depth 20

    $adapterSchema = [ordered]@{
        '$schema' = "https://json-schema.org/draft/2020-12/schema"
        '$id' = "https://github.com/mozartg/media-factory/contracts/adapter.schema.json"
        title = "Media Factory Adapter Manifest"
        type = "object"
        additionalProperties = $false
        required = @("schema","adapter_id","capability","source_repository","status","health_check","invoke","receipt")
        properties = [ordered]@{
            schema = [ordered]@{ const = "media-factory-adapter/v1" }
            adapter_id = [ordered]@{ type = "string"; minLength = 1 }
            capability = [ordered]@{ enum = @("image","audio","motion","video","composition","qa","custody","delivery","orchestration") }
            source_repository = [ordered]@{ type = "string"; minLength = 1 }
            status = [ordered]@{ enum = @("planned","integrating","blocked","canary","verified_once","verified_reproduced","rejected","deprecated") }
            health_check = [ordered]@{ type = "object" }
            invoke = [ordered]@{ type = "object" }
            receipt = [ordered]@{ type = "object" }
        }
    } | ConvertTo-Json -Depth 20

    $consumerSchema = [ordered]@{
        '$schema' = "https://json-schema.org/draft/2020-12/schema"
        '$id' = "https://github.com/mozartg/media-factory/contracts/consumer.schema.json"
        title = "Media Factory Consumer Manifest"
        type = "object"
        additionalProperties = $false
        required = @("schema","consumer_repository","media_factory_repository","capabilities","status","receipts")
        properties = [ordered]@{
            schema = [ordered]@{ const = "media-factory-consumer/v1" }
            consumer_repository = [ordered]@{ type = "string"; minLength = 1 }
            media_factory_repository = [ordered]@{ const = "mozartg/media-factory" }
            capabilities = [ordered]@{ type = "array"; items = [ordered]@{ type = "string" } }
            status = [ordered]@{ type = "string" }
            receipts = [ordered]@{ type = "array"; items = [ordered]@{ type = "string" } }
        }
    } | ConvertTo-Json -Depth 20

    $migration = [ordered]@{
        schema = "media-factory-migration-source/v1"
        source_repository = "mozartg/mgvisuals"
        role = "failed_diy_generator_and_negative_evidence"
        governance_transfer = $false
        allowed_transfer = @("independently reviewed implementation mechanics","tests","schemas","failure receipts")
        required_per_component = @("source path","source SHA-256","README and issue review","classification","target adapter","canary","provider readback")
    } | ConvertTo-Json -Depth 20

    Write-Utf8NoBom -Path (Join-Path $localRoot "README.md") -Content $readme
    Write-Utf8NoBom -Path (Join-Path $localRoot "authority\VERIFIED-STATE-STANDARD.md") -Content $verification
    Write-Utf8NoBom -Path (Join-Path $localRoot "benchmarks\approved\come-as-you-are.json") -Content $benchmark
    Write-Utf8NoBom -Path (Join-Path $localRoot "contracts\adapter.schema.json") -Content $adapterSchema
    Write-Utf8NoBom -Path (Join-Path $localRoot "contracts\consumer.schema.json") -Content $consumerSchema
    Write-Utf8NoBom -Path (Join-Path $localRoot "migration\mgvisuals.json") -Content $migration
    foreach ($folder in @("adapters","workflows","tests","receipts","consumers")) {
        Write-Utf8NoBom -Path (Join-Path $localRoot "$folder\.gitkeep") -Content ""
    }

    & git -C $localRoot add --all
    if ($LASTEXITCODE -ne 0) { throw "git add failed." }
    $pending = @(& git -C $localRoot status --porcelain)
    if ($pending.Count -gt 0) {
        & git -C $localRoot -c user.name="Media Factory Fleet" -c user.email="media-factory@users.noreply.github.com" commit -m "Establish canonical Media Factory baseline" 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "git commit failed." }
        & git -C $localRoot push origin HEAD 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "git push failed." }
    }

    $head = ((& git -C $localRoot rev-parse HEAD 2>&1) | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) { throw "Unable to read local commit." }
    $provider = ((& $gh.Source api "repos/$repo/commits/$head" --jq ".sha" 2>&1) | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $provider -ne $head) { throw "Provider commit readback failed." }

    $receipt = [ordered]@{
        schema = "media-factory-bootstrap-receipt/v1"
        recorded_at = (Get-Date).ToUniversalTime().ToString("o")
        repository = $repo
        repository_url = [string]$meta.html_url
        visibility = [string]$meta.visibility
        default_branch = [string]$meta.default_branch
        created = $created
        existed_before = $existing
        local_path = $localRoot
        commit_sha = $head
        provider_commit_verified = $true
        mgvisuals_governance_transferred = $false
    }
    $receiptPath = Join-Path $receiptRoot ("media-factory-bootstrap-{0}.json" -f (Get-Date -Format "yyyyMMdd-HHmmss"))
    Write-Utf8NoBom -Path $receiptPath -Content ($receipt | ConvertTo-Json -Depth 20)

    return "Repo=$repo; URL=$($meta.html_url); Private=$($meta.private); Default=$($meta.default_branch); Created=$created; Commit=$head; ProviderVerified=True; Receipt=$receiptPath"
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

        "media_factory_bootstrap" {
            return Invoke-MediaFactoryBootstrap
        }

        default { throw "Unknown task: $Task" }
    }
}

Export-ModuleMember -Function Resolve-ControlPath,Invoke-ControlTask
