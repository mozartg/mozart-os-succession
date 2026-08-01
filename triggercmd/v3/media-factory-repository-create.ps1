[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$owner = "mozartg"
$name = "media-factory"
$repository = "$owner/$name"
$receiptRoot = "C:\Users\mozar\TriggerCMD-Scripts\Control\Receipts"
$receiptPath = Join-Path $receiptRoot ("media-factory-provider-create-{0}.json" -f (Get-Date -Format "yyyyMMdd-HHmmss"))
New-Item -ItemType Directory -Force -Path $receiptRoot | Out-Null

function Write-Utf8NoBom {
    param([string]$Path,[string]$Content)
    [IO.File]::WriteAllText($Path,$Content,[Text.UTF8Encoding]::new($false))
}

function Invoke-GhCapture {
    param(
        [Parameter(Mandatory)][string]$GhPath,
        [Parameter(Mandatory)][string[]]$Arguments
    )

    $priorPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $output = @(& $GhPath @Arguments 2>&1)
        $code = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $priorPreference
    }

    return [pscustomobject]@{
        Code = [int]$code
        Text = (($output | Out-String).Trim())
    }
}

function Limit-ProviderText {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $safe = $Text -replace '(?i)(authorization:\s*(?:bearer|token)\s+)[^\s]+','$1[REDACTED]'
    $safe = $safe -replace '(?i)(gh[pousr]_[A-Za-z0-9_]+)','[REDACTED_GITHUB_CREDENTIAL]'
    if ($safe.Length -gt 500) { $safe = $safe.Substring(0,500) }
    return $safe
}

$receipt = [ordered]@{
    schema = "media-factory-provider-create-receipt/v1"
    started_at = (Get-Date).ToUniversalTime().ToString("o")
    completed_at = $null
    repository = $repository
    status = "UNVERIFIED"
    authenticated_login = $null
    oauth_scopes = $null
    precheck_code = $null
    route_attempts = @()
    final_readback_code = $null
    repository_url = $null
    visibility = $null
    default_branch = $null
    created = $false
    credential_disclosed = $false
}

try {
    $gh = Get-Command gh.exe -ErrorAction SilentlyContinue
    if (-not $gh) { $gh = Get-Command gh -ErrorAction SilentlyContinue }
    if (-not $gh) { throw "GitHub CLI not found." }

    $auth = Invoke-GhCapture -GhPath $gh.Source -Arguments @("auth","status","--hostname","github.com")
    if ($auth.Code -ne 0) { throw "GitHub CLI auth status failed: $(Limit-ProviderText $auth.Text)" }

    $user = Invoke-GhCapture -GhPath $gh.Source -Arguments @("api","user","--jq",".login")
    if ($user.Code -ne 0) { throw "Authenticated-user readback failed: $(Limit-ProviderText $user.Text)" }
    $receipt.authenticated_login = $user.Text.Trim()
    if ($receipt.authenticated_login -ne $owner) {
        throw "GitHub CLI is authenticated as '$($receipt.authenticated_login)', not '$owner'."
    }

    $headers = Invoke-GhCapture -GhPath $gh.Source -Arguments @("api","-i","user")
    if ($headers.Code -eq 0) {
        $scopeLine = @($headers.Text -split "`r?`n" | Where-Object { $_ -match '(?i)^x-oauth-scopes:' } | Select-Object -First 1)
        if ($scopeLine.Count -gt 0) {
            $receipt.oauth_scopes = (($scopeLine[0] -split ':',2)[1]).Trim()
        }
    }

    $precheck = Invoke-GhCapture -GhPath $gh.Source -Arguments @("api","repos/$repository")
    $receipt.precheck_code = $precheck.Code

    if ($precheck.Code -ne 0) {
        $routeA = Invoke-GhCapture -GhPath $gh.Source -Arguments @(
            "api","--method","POST","user/repos",
            "-f","name=$name",
            "-f","description=Canonical private Media Factory for benchmarks, adapters, workflows, tests, receipts, and consumer manifests.",
            "-F","private=true",
            "-F","auto_init=true",
            "-F","has_issues=true",
            "-F","has_projects=true",
            "-F","has_wiki=false"
        )
        $receipt.route_attempts += [ordered]@{
            route = "official_rest_authenticated_user"
            exit_code = $routeA.Code
            provider_message = Limit-ProviderText $routeA.Text
        }

        if ($routeA.Code -eq 0) {
            $receipt.created = $true
        }
        else {
            $routeB = Invoke-GhCapture -GhPath $gh.Source -Arguments @(
                "repo","create",$name,
                "--private",
                "--description","Canonical private Media Factory for benchmarks, adapters, workflows, tests, receipts, and consumer manifests.",
                "--add-readme"
            )
            $receipt.route_attempts += [ordered]@{
                route = "gh_cli_authenticated_user_default_owner"
                exit_code = $routeB.Code
                provider_message = Limit-ProviderText $routeB.Text
            }
            if ($routeB.Code -eq 0) { $receipt.created = $true }
        }
    }

    Start-Sleep -Seconds 2
    $verify = Invoke-GhCapture -GhPath $gh.Source -Arguments @("api","repos/$repository")
    $receipt.final_readback_code = $verify.Code
    if ($verify.Code -ne 0) {
        $receipt.status = "BLOCKED_PROVIDER_CREATE_OR_PERMISSION"
        throw "Provider readback failed after all creation routes: $(Limit-ProviderText $verify.Text)"
    }

    $meta = $verify.Text | ConvertFrom-Json
    $receipt.repository_url = [string]$meta.html_url
    $receipt.visibility = [string]$meta.visibility
    $receipt.default_branch = [string]$meta.default_branch

    if (-not [bool]$meta.private -or [string]$meta.visibility -ne "private") {
        $receipt.status = "CONTRADICTED_VISIBILITY_NOT_PRIVATE"
        throw "Provider readback did not confirm a private repository."
    }

    $receipt.status = "VERIFIED_COMPLETE"
    $receipt.completed_at = (Get-Date).ToUniversalTime().ToString("o")
    Write-Utf8NoBom -Path $receiptPath -Content ($receipt | ConvertTo-Json -Depth 20)
    $digest = (Get-FileHash -LiteralPath $receiptPath -Algorithm SHA256).Hash.ToLowerInvariant()
    Write-Utf8NoBom -Path ($receiptPath + ".sha256") -Content "$digest  $([IO.Path]::GetFileName($receiptPath))`n"

    Write-Output "Repo=$repository; URL=$($receipt.repository_url); Private=True; Created=$($receipt.created); Default=$($receipt.default_branch); Receipt=$receiptPath"
    exit 0
}
catch {
    if ($receipt.status -eq "UNVERIFIED") { $receipt.status = "FAILED" }
    $receipt.completed_at = (Get-Date).ToUniversalTime().ToString("o")
    $receipt.error = $_.Exception.Message
    Write-Utf8NoBom -Path $receiptPath -Content ($receipt | ConvertTo-Json -Depth 20)
    $digest = (Get-FileHash -LiteralPath $receiptPath -Algorithm SHA256).Hash.ToLowerInvariant()
    Write-Utf8NoBom -Path ($receiptPath + ".sha256") -Content "$digest  $([IO.Path]::GetFileName($receiptPath))`n"
    Write-Error "Media Factory provider creation failed: $($_.Exception.Message)"
    exit 1
}
