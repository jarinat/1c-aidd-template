<#
.SYNOPSIS
Prepares a GitLab merge request review worktree and normalized review inputs.

.DESCRIPTION
Creates or reuses a detached review worktree under C:\ai-review-wt, fetches the
MR refs, writes a manifest and diff files under C:\ai-review-wt\_manifests,
and prints the manifest JSON to stdout.

The script intentionally does not publish comments, approve, merge, checkout
the user's current branch, or accept arbitrary shell code.

.EXAMPLE
.claude/scripts/gitlab-mr-review.cmd prepare -MrUrl https://gitlab.example.com/group/project/-/merge_requests/123

.EXAMPLE
.claude/scripts/gitlab-mr-review.cmd cleanup -WorktreePath C:\ai-review-wt\project-review-mr-123-abcdef12
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0, Mandatory = $true)]
    [ValidateSet("help", "prepare", "cleanup")]
    [string]$Command,

    [string]$MrUrl,

    [string]$WorktreePath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

try {
    [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false
    $OutputEncoding = [Console]::OutputEncoding
} catch {
    # Keep the default output encoding if the host does not allow changing it.
}

$ProjectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$ProjectRootFull = [System.IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\', '/')
$ReviewRoot = "C:\ai-review-wt"

function Stop-WithMessage {
    param([Parameter(Mandatory = $true)][string]$Message)

    [Console]::Error.WriteLine($Message)
    exit 2
}

function Show-Help {
    @"
Usage:
  gitlab-mr-review.cmd help
  gitlab-mr-review.cmd prepare -MrUrl <gitlab-merge-request-url>
  gitlab-mr-review.cmd cleanup -WorktreePath <worktree-path>

Implementation:
  gitlab-mr-review.ps1 is called by the .cmd wrapper. Claude Code should use
  gitlab-mr-review.cmd as the external entrypoint.

prepare:
  - parses the MR URL
  - reads GitLab metadata through the GitLab API
  - fetches target branch and MR head ref without switching the current branch
  - creates or reuses a detached worktree under C:\ai-review-wt
  - writes manifest.json, mr.json, diff-stat.txt, diff-name-status.txt, diff.patch
  - prints manifest JSON to stdout

cleanup:
  - removes only worktrees located under C:\ai-review-wt
  - runs git worktree prune

Authentication:
  Uses only glab auth for GitLab API calls. Tokens from environment variables
  or git credential manager are intentionally not used.
"@
}

function Invoke-Tool {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [string]$FailureMessage = "Command failed"
    )

    $output = & $FilePath @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        $text = ($output | Out-String).Trim()
        if ([string]::IsNullOrWhiteSpace($text)) {
            $text = "exit code $LASTEXITCODE"
        }
        Stop-WithMessage "$FailureMessage`: $text"
    }

    return @($output)
}

function Get-ToolOutput {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [string]$FailureMessage = "Command failed"
    )

    return (Invoke-Tool -FilePath $FilePath -Arguments $Arguments -FailureMessage $FailureMessage | Out-String).Trim()
}

function ConvertTo-SafeName {
    param([Parameter(Mandatory = $true)][string]$Value)

    $safe = $Value -replace "[^A-Za-z0-9._-]", "-"
    $safe = $safe.Trim("-")
    if ([string]::IsNullOrWhiteSpace($safe)) {
        return "repo"
    }

    return $safe
}

function Get-FullPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    return [System.IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
}

function Test-IsInsideDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Root
    )

    $fullPath = Get-FullPath $Path
    $fullRoot = Get-FullPath $Root
    $comparison = [System.StringComparison]::OrdinalIgnoreCase

    return $fullPath.StartsWith($fullRoot + [System.IO.Path]::DirectorySeparatorChar, $comparison) -or
        $fullPath.StartsWith($fullRoot + [System.IO.Path]::AltDirectorySeparatorChar, $comparison)
}

function Parse-MrUrl {
    param([Parameter(Mandatory = $true)][string]$Url)

    $pattern = "^https?://(?<host>[^/]+)/(?<project>.+)/-/merge_requests/(?<iid>[0-9]+)(?:[/?#].*)?$"
    $match = [regex]::Match($Url, $pattern)
    if (-not $match.Success) {
        Stop-WithMessage "Unsupported GitLab MR URL: $Url"
    }

    [pscustomobject]@{
        Host = $match.Groups["host"].Value
        ProjectPath = [System.Uri]::UnescapeDataString($match.Groups["project"].Value).Trim("/")
        Iid = $match.Groups["iid"].Value
    }
}

function Invoke-GlabApiGet {
    param(
        [Parameter(Mandatory = $true)][string]$Endpoint,
        [Parameter(Mandatory = $true)][string]$HostName
    )

    if ($null -eq (Get-Command glab -ErrorAction SilentlyContinue)) {
        Stop-WithMessage "glab is not available in PATH. Install glab or fix the terminal PATH, then run 'glab auth login --hostname $HostName'."
    }

    $authOutput = & glab auth status --hostname $HostName 2>&1
    if ($LASTEXITCODE -ne 0) {
        $text = ($authOutput | Out-String).Trim()
        if ([string]::IsNullOrWhiteSpace($text)) {
            $text = "glab auth status failed"
        }
        Stop-WithMessage "glab is not authenticated for $HostName. Run 'glab auth login --hostname $HostName' outside Claude Code. $text"
    }

    $output = & glab api --hostname $HostName $Endpoint 2>&1
    if ($LASTEXITCODE -ne 0) {
        $text = ($output | Out-String).Trim()
        if ([string]::IsNullOrWhiteSpace($text)) {
            $text = "glab api failed"
        }
        Stop-WithMessage "glab API request failed for $HostName/$Endpoint. Check glab auth token scopes and project access. $text"
    }

    $json = ($output | Out-String).Trim()
    if ([string]::IsNullOrWhiteSpace($json)) {
        Stop-WithMessage "glab API returned an empty response for $HostName/$Endpoint"
    }

    try {
        return $json | ConvertFrom-Json
    } catch {
        Stop-WithMessage "glab API returned invalid JSON for $HostName/$Endpoint"
    }
}

function Invoke-GitLabGet {
    param(
        [Parameter(Mandatory = $true)][string]$Endpoint,
        [Parameter(Mandatory = $true)][string]$HostName
    )

    return Invoke-GlabApiGet -Endpoint $Endpoint -HostName $HostName
}

function Convert-RemoteUrl {
    param([Parameter(Mandatory = $true)][string]$Url)

    $remote = $Url.Trim()
    $hostName = $null
    $projectPath = $null

    if ($remote -match "^https?://(?<host>[^/]+)/(?<path>.+?)(?:\.git)?/?$") {
        $hostName = $matches["host"]
        $projectPath = $matches["path"]
    } elseif ($remote -match "^ssh://(?:[^@/]+@)?(?<host>[^/]+)/(?<path>.+?)(?:\.git)?/?$") {
        $hostName = $matches["host"]
        $projectPath = $matches["path"]
    } elseif ($remote -match "^(?:[^@]+@)?(?<host>[^:]+):(?<path>.+?)(?:\.git)?$") {
        $hostName = $matches["host"]
        $projectPath = $matches["path"]
    }

    if ([string]::IsNullOrWhiteSpace($hostName) -or [string]::IsNullOrWhiteSpace($projectPath)) {
        return $null
    }

    if ($projectPath.EndsWith(".git", [System.StringComparison]::OrdinalIgnoreCase)) {
        $projectPath = $projectPath.Substring(0, $projectPath.Length - 4)
    }

    [pscustomobject]@{
        Host = $hostName
        ProjectPath = $projectPath.Trim("/")
    }
}

function Get-MatchingRemote {
    param(
        [Parameter(Mandatory = $true)][string]$HostName,
        [Parameter(Mandatory = $true)][string]$ProjectPath
    )

    $remoteLines = Invoke-Tool -FilePath "git" -Arguments @("-C", $ProjectRootFull, "remote", "-v") -FailureMessage "git remote -v failed"
    foreach ($line in $remoteLines) {
        if ($line -notmatch "^(?<name>\S+)\s+(?<url>\S+)\s+\(fetch\)$") {
            continue
        }

        $parsed = Convert-RemoteUrl -Url $matches["url"]
        if ($null -eq $parsed) {
            continue
        }

        if (
            $parsed.Host.Equals($HostName, [System.StringComparison]::OrdinalIgnoreCase) -and
            $parsed.ProjectPath.Equals($ProjectPath, [System.StringComparison]::OrdinalIgnoreCase)
        ) {
            return [pscustomobject]@{
                Name = $matches["name"]
                Url = $matches["url"]
            }
        }
    }

    return $null
}

function Get-WorktreeHead {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        return $null
    }

    try {
        return Get-ToolOutput -FilePath "git" -Arguments @("-C", $Path, "rev-parse", "HEAD") -FailureMessage "git rev-parse failed"
    } catch {
        return $null
    }
}

function New-UniqueWorktreePath {
    param([Parameter(Mandatory = $true)][string]$BasePath)

    if (-not (Test-Path -LiteralPath $BasePath)) {
        return $BasePath
    }

    for ($index = 1; $index -le 99; $index++) {
        $candidate = "$BasePath-$index"
        if (-not (Test-Path -LiteralPath $candidate)) {
            return $candidate
        }
    }

    Stop-WithMessage "Cannot find a free worktree path near: $BasePath"
}

function Write-Utf8File {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content
    )

    [System.IO.File]::WriteAllText($Path, $Content, (New-Object System.Text.UTF8Encoding $false))
}

function Save-GitOutput {
    param(
        [Parameter(Mandatory = $true)][string]$Worktree,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$OutputPath,
        [Parameter(Mandatory = $true)][string]$FailureMessage
    )

    $output = Invoke-Tool -FilePath "git" -Arguments (@("-C", $Worktree) + $Arguments) -FailureMessage $FailureMessage
    Write-Utf8File -Path $OutputPath -Content (($output | Out-String).TrimEnd() + "`n")
}

function Prepare-Review {
    if ([string]::IsNullOrWhiteSpace($MrUrl)) {
        Stop-WithMessage "prepare requires -MrUrl"
    }

    $urlInfo = Parse-MrUrl -Url $MrUrl
    $encodedProject = [System.Uri]::EscapeDataString($urlInfo.ProjectPath)
    $mrEndpoint = "projects/$encodedProject/merge_requests/$($urlInfo.Iid)"
    $mr = Invoke-GitLabGet -Endpoint $mrEndpoint -HostName $urlInfo.Host

    $targetProjectId = if ($null -ne $mr.target_project_id) { $mr.target_project_id } else { $mr.project_id }
    if ($null -eq $targetProjectId) {
        Stop-WithMessage "MR metadata does not contain target project id"
    }

    $targetProjectEndpoint = "projects/$targetProjectId"
    $targetProject = Invoke-GitLabGet -Endpoint $targetProjectEndpoint -HostName $urlInfo.Host
    $targetProjectPath = $targetProject.path_with_namespace
    if ([string]::IsNullOrWhiteSpace($targetProjectPath)) {
        Stop-WithMessage "Target project metadata does not contain path_with_namespace"
    }

    $remote = Get-MatchingRemote -HostName $urlInfo.Host -ProjectPath $targetProjectPath
    if ($null -eq $remote) {
        Stop-WithMessage "Current repository remote does not match GitLab target project $($urlInfo.Host)/$targetProjectPath"
    }

    if ($null -eq $mr.diff_refs) {
        Stop-WithMessage "MR diff_refs are not ready yet. Repeat later after GitLab prepares the MR diff."
    }

    $baseSha = $mr.diff_refs.base_sha
    $headSha = $mr.diff_refs.head_sha
    if ([string]::IsNullOrWhiteSpace($baseSha) -or [string]::IsNullOrWhiteSpace($headSha)) {
        Stop-WithMessage "MR diff_refs are not ready yet. Repeat later after GitLab prepares the MR diff."
    }

    $targetBranch = $mr.target_branch
    $sourceBranch = $mr.source_branch
    if ([string]::IsNullOrWhiteSpace($targetBranch) -or [string]::IsNullOrWhiteSpace($sourceBranch)) {
        Stop-WithMessage "MR metadata does not contain source_branch or target_branch"
    }

    Invoke-Tool -FilePath "git" -Arguments @("-C", $ProjectRootFull, "fetch", $remote.Name, $targetBranch) -FailureMessage "git fetch target branch failed" | Out-Null

    $mrHeadRef = "refs/merge-requests/$($urlInfo.Iid)/head:refs/remotes/$($remote.Name)/mr/$($urlInfo.Iid)/head"
    $mrHeadFetched = $true
    $fetchOutput = & git -C $ProjectRootFull fetch $remote.Name $mrHeadRef 2>&1
    if ($LASTEXITCODE -ne 0) {
        $mrHeadFetched = $false
    }

    if (-not $mrHeadFetched) {
        if ($mr.source_project_id -ne $targetProjectId) {
            $text = ($fetchOutput | Out-String).Trim()
            Stop-WithMessage "Cannot fetch MR head ref and MR source project differs from target project. Add a source remote or make the MR head ref available. $text"
        }

        Invoke-Tool -FilePath "git" -Arguments @("-C", $ProjectRootFull, "fetch", $remote.Name, $sourceBranch) -FailureMessage "git fetch source branch failed" | Out-Null
    }

    Invoke-Tool -FilePath "git" -Arguments @("-C", $ProjectRootFull, "cat-file", "-e", "$baseSha^{commit}") -FailureMessage "base_sha is not available locally after fetch" | Out-Null
    Invoke-Tool -FilePath "git" -Arguments @("-C", $ProjectRootFull, "cat-file", "-e", "$headSha^{commit}") -FailureMessage "head_sha is not available locally after fetch" | Out-Null

    if (-not (Test-Path -LiteralPath $ReviewRoot -PathType Container)) {
        New-Item -ItemType Directory -Path $ReviewRoot -Force | Out-Null
    }

    $repoName = ConvertTo-SafeName (($targetProjectPath -split "/")[-1] -replace "\.git$", "")
    $shortSha = $headSha.Substring(0, [Math]::Min(8, $headSha.Length))
    $baseWorktreePath = Join-Path -Path $ReviewRoot -ChildPath "$repoName-review-mr-$($urlInfo.Iid)-$shortSha"
    $resolvedWorktreePath = Get-FullPath $baseWorktreePath
    $reused = $false

    if (Test-Path -LiteralPath $resolvedWorktreePath -PathType Container) {
        $existingHead = Get-WorktreeHead -Path $resolvedWorktreePath
        if ($existingHead -eq $headSha) {
            $reused = $true
        } else {
            $resolvedWorktreePath = New-UniqueWorktreePath -BasePath $resolvedWorktreePath
        }
    }

    if (-not $reused) {
        Invoke-Tool -FilePath "git" -Arguments @("-C", $ProjectRootFull, "-c", "core.longpaths=true", "worktree", "add", "--detach", $resolvedWorktreePath, $headSha) -FailureMessage "git worktree add failed" | Out-Null
    }

    $manifestRoot = Join-Path -Path $ReviewRoot -ChildPath "_manifests"
    $manifestDirectory = Join-Path -Path $manifestRoot -ChildPath "$repoName-mr-$($urlInfo.Iid)-$shortSha"
    if (-not (Test-Path -LiteralPath $manifestDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $manifestDirectory -Force | Out-Null
    }

    $mrJsonPath = Join-Path -Path $manifestDirectory -ChildPath "mr.json"
    $statPath = Join-Path -Path $manifestDirectory -ChildPath "diff-stat.txt"
    $nameStatusPath = Join-Path -Path $manifestDirectory -ChildPath "diff-name-status.txt"
    $diffPath = Join-Path -Path $manifestDirectory -ChildPath "diff.patch"
    $manifestPath = Join-Path -Path $manifestDirectory -ChildPath "manifest.json"

    Write-Utf8File -Path $mrJsonPath -Content (($mr | ConvertTo-Json -Depth 20) + "`n")
    Save-GitOutput -Worktree $resolvedWorktreePath -Arguments @("diff", "$baseSha...$headSha", "--stat") -OutputPath $statPath -FailureMessage "git diff --stat failed"
    Save-GitOutput -Worktree $resolvedWorktreePath -Arguments @("diff", "$baseSha...$headSha", "--name-status", "--find-renames") -OutputPath $nameStatusPath -FailureMessage "git diff --name-status failed"
    Save-GitOutput -Worktree $resolvedWorktreePath -Arguments @("diff", "$baseSha...$headSha", "--find-renames") -OutputPath $diffPath -FailureMessage "git diff failed"

    $manifest = [pscustomobject]@{
        schema = "gitlab-mr-review.v1"
        mr_url = $mr.web_url
        title = $mr.title
        description = $mr.description
        state = $mr.state
        source_branch = $sourceBranch
        target_branch = $targetBranch
        source_project_id = $mr.source_project_id
        target_project_id = $targetProjectId
        target_project_path = $targetProjectPath
        base_sha = $baseSha
        head_sha = $headSha
        remote = $remote.Name
        mr_head_ref_fetched = $mrHeadFetched
        worktree_path = $resolvedWorktreePath
        worktree_reused = $reused
        manifest_path = $manifestPath
        mr_json_path = $mrJsonPath
        diff_stat_path = $statPath
        diff_name_status_path = $nameStatusPath
        diff_patch_path = $diffPath
        cleanup_command = ".claude/scripts/gitlab-mr-review.cmd cleanup -WorktreePath `"$resolvedWorktreePath`""
    }

    $manifestJson = $manifest | ConvertTo-Json -Depth 20
    Write-Utf8File -Path $manifestPath -Content ($manifestJson + "`n")
    $manifestJson
}

function Cleanup-Review {
    if ([string]::IsNullOrWhiteSpace($WorktreePath)) {
        Stop-WithMessage "cleanup requires -WorktreePath"
    }

    $resolvedPath = Get-FullPath $WorktreePath
    if (-not (Test-IsInsideDirectory -Path $resolvedPath -Root $ReviewRoot)) {
        Stop-WithMessage "Refusing to remove a path that is not a child worktree under $ReviewRoot`: $resolvedPath"
    }

    $removed = $false
    if (Test-Path -LiteralPath $resolvedPath -PathType Container) {
        Invoke-Tool -FilePath "git" -Arguments @("-C", $ProjectRootFull, "worktree", "remove", "--force", $resolvedPath) -FailureMessage "git worktree remove failed" | Out-Null
        $removed = $true
    }

    Invoke-Tool -FilePath "git" -Arguments @("-C", $ProjectRootFull, "worktree", "prune") -FailureMessage "git worktree prune failed" | Out-Null

    [pscustomobject]@{
        schema = "gitlab-mr-review-cleanup.v1"
        worktree_path = $resolvedPath
        removed = $removed
    } | ConvertTo-Json -Depth 5
}

switch ($Command) {
    "help" {
        Show-Help
    }

    "prepare" {
        Prepare-Review
    }

    "cleanup" {
        Cleanup-Review
    }
}
