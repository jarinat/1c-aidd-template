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

.EXAMPLE
.claude/scripts/gitlab-mr-review.cmd show-file -WorktreePath C:\ai-review-wt\project-review-mr-123-abcdef12 -Ref abcdef1234 -RepoPath src/cf/src/CommonModules/Example/Module.bsl

.EXAMPLE
.claude/scripts/gitlab-mr-review.cmd grep-file -WorktreePath C:\ai-review-wt\project-review-mr-123-abcdef12 -Ref abcdef1234 -RepoPath src/cf/src/CommonModules/Example/Module.bsl -Pattern "Процедура" -First 30
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0, Mandatory = $true)]
    [ValidateSet("help", "prepare", "cleanup", "show-file", "grep-file", "list-files", "grep-tree")]
    [string]$Command,

    [string]$MrUrl,

    [string]$WorktreePath,

    [string]$Ref,

    [string]$RepoPath,

    [string]$Pattern,

    [int]$First = 0
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
  gitlab-mr-review.cmd show-file -WorktreePath <worktree-path> -Ref <sha-or-ref> -RepoPath <repo-relative-path>
  gitlab-mr-review.cmd grep-file -WorktreePath <worktree-path> -Ref <sha-or-ref> -RepoPath <repo-relative-path> -Pattern <regex> [-First <count>]
  gitlab-mr-review.cmd list-files -WorktreePath <worktree-path> -Ref <sha-or-ref> -RepoPath <repo-relative-prefix>
  gitlab-mr-review.cmd grep-tree -WorktreePath <worktree-path> -Ref <sha-or-ref> -Pattern <regex> [-RepoPath <repo-relative-prefix>] [-First <count>]

Implementation:
  gitlab-mr-review.ps1 is called by the .cmd wrapper. Claude Code should use
  gitlab-mr-review.cmd as the external entrypoint.

prepare:
  - parses the MR URL
  - reads GitLab metadata through the GitLab API
  - fetches target branch and MR head ref without switching the current branch
  - creates or reuses a detached worktree under C:\ai-review-wt
  - writes manifest.json, mr.json, diff-stat.txt, diff-name-status.txt, diff.patch,
    changed-files.json, and text snapshots for changed files
  - prints manifest JSON to stdout

cleanup:
  - removes only worktrees located under C:\ai-review-wt
  - runs git worktree prune

read-only context:
  - show-file prints one file from a ref
  - grep-file prints matching lines from one file as <line>:<text>
  - list-files lists files under a repo-relative prefix at a ref
  - grep-tree searches text through a ref and prints git-grep style matches
  - grep-file and grep-tree support -First <count> instead of shell pipes like
    Select-Object -First or tail/head
  - all read-only commands require WorktreePath under C:\ai-review-wt and
    reject rooted paths, parent traversal, shell metachar refs, and ad-hoc
    shell pipelines

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

    $result = Invoke-NativeCommand -FilePath $FilePath -Arguments $Arguments

    if ($result.ExitCode -ne 0) {
        $text = ($result.Output | Out-String).Trim()
        if ([string]::IsNullOrWhiteSpace($text)) {
            $text = "exit code $($result.ExitCode)"
        }
        Stop-WithMessage "$FailureMessage`: $text"
    }

    return @($result.Output)
}

function Get-ToolOutput {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [string]$FailureMessage = "Command failed"
    )

    return (Invoke-Tool -FilePath $FilePath -Arguments $Arguments -FailureMessage $FailureMessage | Out-String).Trim()
}

function Invoke-NativeCommand {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    if ($null -eq (Get-Command $FilePath -ErrorAction SilentlyContinue)) {
        Stop-WithMessage "Command is not available in PATH: $FilePath"
    }

    $previousErrorActionPreference = $ErrorActionPreference
    $nativePreferenceExists = Test-Path Variable:\PSNativeCommandUseErrorActionPreference
    if ($nativePreferenceExists) {
        $previousNativePreference = $PSNativeCommandUseErrorActionPreference
    }

    try {
        # Native tools may write progress to stderr with a zero exit code.
        # Keep strict mode for the script, but route all native status through
        # LASTEXITCODE instead of PowerShell NativeCommandError.
        $script:ErrorActionPreference = "Continue"
        if ($nativePreferenceExists) {
            $script:PSNativeCommandUseErrorActionPreference = $false
        }

        $output = & $FilePath @Arguments 2>&1
        $exitCode = $LASTEXITCODE
    } finally {
        $script:ErrorActionPreference = $previousErrorActionPreference
        if ($nativePreferenceExists) {
            $script:PSNativeCommandUseErrorActionPreference = $previousNativePreference
        }
    }

    [pscustomobject]@{
        ExitCode = $exitCode
        Output = @($output)
    }
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

function Resolve-ReviewWorktree {
    param([Parameter(Mandatory = $true)][string]$Path)

    $resolvedPath = Get-FullPath $Path
    if (-not (Test-IsInsideDirectory -Path $resolvedPath -Root $ReviewRoot)) {
        Stop-WithMessage "Refusing to read a path that is not a child worktree under $ReviewRoot`: $resolvedPath"
    }

    if (-not (Test-Path -LiteralPath $resolvedPath -PathType Container)) {
        Stop-WithMessage "Review worktree does not exist: $resolvedPath"
    }

    $isWorktree = Get-ToolOutput -FilePath "git" -Arguments @("-C", $resolvedPath, "rev-parse", "--is-inside-work-tree") -FailureMessage "git rev-parse failed"
    if ($isWorktree -ne "true") {
        Stop-WithMessage "Path is not a git worktree: $resolvedPath"
    }

    return $resolvedPath
}

function Assert-SafeRef {
    param([Parameter(Mandatory = $true)][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        Stop-WithMessage "Ref is required"
    }

    if (
        $Value -notmatch "^[A-Za-z0-9._/-]+$" -or
        $Value.Contains("..") -or
        $Value.Contains("@{") -or
        $Value.StartsWith("/") -or
        $Value.EndsWith("/") -or
        $Value.Contains("\")
    ) {
        Stop-WithMessage "Unsupported ref syntax: $Value"
    }
}

function Normalize-RepoPath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [switch]$AllowEmpty
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        if ($AllowEmpty) {
            return "."
        }
        Stop-WithMessage "RepoPath is required"
    }

    if ([System.IO.Path]::IsPathRooted($Path)) {
        Stop-WithMessage "RepoPath must be relative to the repository: $Path"
    }

    $normalized = ($Path -replace "\\", "/").Trim("/")
    if ([string]::IsNullOrWhiteSpace($normalized)) {
        if ($AllowEmpty) {
            return "."
        }
        Stop-WithMessage "RepoPath is required"
    }

    if ($normalized.Contains(":")) {
        Stop-WithMessage "RepoPath must not contain ':': $Path"
    }

    $parts = $normalized -split "/"
    foreach ($part in $parts) {
        if ([string]::IsNullOrWhiteSpace($part) -or $part -eq "." -or $part -eq "..") {
            Stop-WithMessage "RepoPath must not contain empty, current, or parent segments: $Path"
        }
    }

    return $normalized
}

function Assert-RegexPattern {
    param([Parameter(Mandatory = $true)][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        Stop-WithMessage "Pattern is required"
    }

    try {
        [regex]::new($Value) | Out-Null
    } catch {
        Stop-WithMessage "Pattern is not a valid .NET regular expression: $Value"
    }
}

function Assert-FirstCount {
    param([int]$Value)

    if ($Value -lt 0) {
        Stop-WithMessage "First must be greater than or equal to zero"
    }
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

    $authResult = Invoke-NativeCommand -FilePath "glab" -Arguments @("auth", "status", "--hostname", $HostName)
    if ($authResult.ExitCode -ne 0) {
        $text = ($authResult.Output | Out-String).Trim()
        if ([string]::IsNullOrWhiteSpace($text)) {
            $text = "glab auth status failed"
        }
        Stop-WithMessage "glab is not authenticated for $HostName. Run 'glab auth login --hostname $HostName' outside Claude Code. $text"
    }

    $apiResult = Invoke-NativeCommand -FilePath "glab" -Arguments @("api", "--hostname", $HostName, $Endpoint)
    if ($apiResult.ExitCode -ne 0) {
        $text = ($apiResult.Output | Out-String).Trim()
        if ([string]::IsNullOrWhiteSpace($text)) {
            $text = "glab api failed"
        }
        Stop-WithMessage "glab API request failed for $HostName/$Endpoint. Check glab auth token scopes and project access. $text"
    }

    $json = ($apiResult.Output | Out-String).Trim()
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

function Ensure-Directory {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Join-ManifestRepoPath {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$RepoPath
    )

    $repoRelativePath = Normalize-RepoPath -Path $RepoPath
    $parts = $repoRelativePath -split "/"
    $result = $Root
    foreach ($part in $parts) {
        $result = Join-Path -Path $result -ChildPath $part
    }

    return $result
}

function Test-ReviewTextPath {
    param([Parameter(Mandatory = $true)][string]$RepoPath)

    $extension = [System.IO.Path]::GetExtension($RepoPath).ToLowerInvariant()
    $textExtensions = @(
        ".bsl", ".mdo", ".form", ".xml", ".json", ".txt", ".md", ".yml",
        ".yaml", ".dcss", ".css", ".html", ".htm", ".sql", ".os", ".properties"
    )

    return $textExtensions -contains $extension
}

function Save-GitObjectText {
    param(
        [Parameter(Mandatory = $true)][string]$Worktree,
        [Parameter(Mandatory = $true)][string]$Ref,
        [Parameter(Mandatory = $true)][string]$RepoPath,
        [Parameter(Mandatory = $true)][string]$OutputPath
    )

    $repoRelativePath = Normalize-RepoPath -Path $RepoPath
    $objectName = "${Ref}:$repoRelativePath"
    $content = Invoke-Tool -FilePath "git" -Arguments @("-C", $Worktree, "-c", "core.quotePath=false", "show", $objectName) -FailureMessage "git show failed"
    $parent = Split-Path -Parent $OutputPath
    Ensure-Directory -Path $parent
    Write-Utf8File -Path $OutputPath -Content (($content | Out-String).TrimEnd() + "`n")
}

function Save-GitOutput {
    param(
        [Parameter(Mandatory = $true)][string]$Worktree,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$OutputPath,
        [Parameter(Mandatory = $true)][string]$FailureMessage
    )

    $output = Invoke-Tool -FilePath "git" -Arguments (@("-C", $Worktree, "-c", "core.quotePath=false") + $Arguments) -FailureMessage $FailureMessage
    Write-Utf8File -Path $OutputPath -Content (($output | Out-String).TrimEnd() + "`n")
}

function Get-ChangedFiles {
    param(
        [Parameter(Mandatory = $true)][string]$Worktree,
        [Parameter(Mandatory = $true)][string]$BaseSha,
        [Parameter(Mandatory = $true)][string]$HeadSha
    )

    $lines = Invoke-Tool -FilePath "git" -Arguments @("-C", $Worktree, "-c", "core.quotePath=false", "diff", "$BaseSha...$HeadSha", "--name-status", "--find-renames") -FailureMessage "git diff --name-status failed"
    $items = @()
    foreach ($line in $lines) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        $columns = $line -split "`t"
        if ($columns.Count -lt 2) {
            continue
        }

        $status = $columns[0]
        if ($status.StartsWith("R") -or $status.StartsWith("C")) {
            if ($columns.Count -lt 3) {
                continue
            }

            $items += [pscustomobject]@{
                status = $status
                old_path = Normalize-RepoPath -Path $columns[1]
                path = Normalize-RepoPath -Path $columns[2]
            }
        } else {
            $items += [pscustomobject]@{
                status = $status
                old_path = $null
                path = Normalize-RepoPath -Path $columns[1]
            }
        }
    }

    return $items
}

function Save-ReviewSnapshots {
    param(
        [Parameter(Mandatory = $true)][string]$Worktree,
        [Parameter(Mandatory = $true)][string]$BaseSha,
        [Parameter(Mandatory = $true)][string]$HeadSha,
        [Parameter(Mandatory = $true)][object[]]$ChangedFiles,
        [Parameter(Mandatory = $true)][string]$SnapshotRoot
    )

    $baseRoot = Join-Path -Path $SnapshotRoot -ChildPath "base"
    $headRoot = Join-Path -Path $SnapshotRoot -ChildPath "head"
    Ensure-Directory -Path $baseRoot
    Ensure-Directory -Path $headRoot

    $results = @()
    foreach ($file in $ChangedFiles) {
        $status = [string]$file.status
        $path = [string]$file.path
        $oldPath = if ($null -ne $file.old_path) { [string]$file.old_path } else { $null }
        $baseRepoPath = if ($oldPath) { $oldPath } else { $path }
        $isText = (Test-ReviewTextPath -RepoPath $path) -or ($oldPath -and (Test-ReviewTextPath -RepoPath $oldPath))
        $baseSnapshotPath = $null
        $headSnapshotPath = $null

        if ($isText -and -not $status.StartsWith("A")) {
            $baseSnapshotPath = Join-ManifestRepoPath -Root $baseRoot -RepoPath $baseRepoPath
            Save-GitObjectText -Worktree $Worktree -Ref $BaseSha -RepoPath $baseRepoPath -OutputPath $baseSnapshotPath
        }

        if ($isText -and -not $status.StartsWith("D")) {
            $headSnapshotPath = Join-ManifestRepoPath -Root $headRoot -RepoPath $path
            Save-GitObjectText -Worktree $Worktree -Ref $HeadSha -RepoPath $path -OutputPath $headSnapshotPath
        }

        $results += [pscustomobject]@{
            status = $status
            path = $path
            old_path = $oldPath
            is_text_snapshot = $isText
            base_snapshot_path = $baseSnapshotPath
            head_snapshot_path = $headSnapshotPath
        }
    }

    return $results
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
    $fetchResult = Invoke-NativeCommand -FilePath "git" -Arguments @("-C", $ProjectRootFull, "fetch", $remote.Name, $mrHeadRef)
    if ($fetchResult.ExitCode -ne 0) {
        $mrHeadFetched = $false
    }

    if (-not $mrHeadFetched) {
        if ($mr.source_project_id -ne $targetProjectId) {
            $text = ($fetchResult.Output | Out-String).Trim()
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
    $changedFilesPath = Join-Path -Path $manifestDirectory -ChildPath "changed-files.json"
    $snapshotRoot = Join-Path -Path $manifestDirectory -ChildPath "files"
    $manifestPath = Join-Path -Path $manifestDirectory -ChildPath "manifest.json"

    if (Test-Path -LiteralPath $snapshotRoot -PathType Container) {
        Remove-Item -LiteralPath $snapshotRoot -Recurse -Force
    }

    Write-Utf8File -Path $mrJsonPath -Content (($mr | ConvertTo-Json -Depth 20) + "`n")
    Save-GitOutput -Worktree $resolvedWorktreePath -Arguments @("diff", "$baseSha...$headSha", "--stat") -OutputPath $statPath -FailureMessage "git diff --stat failed"
    Save-GitOutput -Worktree $resolvedWorktreePath -Arguments @("diff", "$baseSha...$headSha", "--name-status", "--find-renames") -OutputPath $nameStatusPath -FailureMessage "git diff --name-status failed"
    Save-GitOutput -Worktree $resolvedWorktreePath -Arguments @("diff", "$baseSha...$headSha", "--find-renames") -OutputPath $diffPath -FailureMessage "git diff failed"
    $changedFiles = Get-ChangedFiles -Worktree $resolvedWorktreePath -BaseSha $baseSha -HeadSha $headSha
    $snapshotFiles = Save-ReviewSnapshots -Worktree $resolvedWorktreePath -BaseSha $baseSha -HeadSha $headSha -ChangedFiles $changedFiles -SnapshotRoot $snapshotRoot
    Write-Utf8File -Path $changedFilesPath -Content (($snapshotFiles | ConvertTo-Json -Depth 10) + "`n")

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
        changed_files_path = $changedFilesPath
        snapshot_root = $snapshotRoot
        base_snapshot_root = (Join-Path -Path $snapshotRoot -ChildPath "base")
        head_snapshot_root = (Join-Path -Path $snapshotRoot -ChildPath "head")
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
        Invoke-Tool -FilePath "git" -Arguments @("-C", $ProjectRootFull, "-c", "core.longpaths=true", "worktree", "remove", "--force", $resolvedPath) -FailureMessage "git worktree remove failed" | Out-Null
        $removed = $true
    }

    Invoke-Tool -FilePath "git" -Arguments @("-C", $ProjectRootFull, "-c", "core.longpaths=true", "worktree", "prune") -FailureMessage "git worktree prune failed" | Out-Null

    [pscustomobject]@{
        schema = "gitlab-mr-review-cleanup.v1"
        worktree_path = $resolvedPath
        removed = $removed
    } | ConvertTo-Json -Depth 5
}

function Show-ReviewFile {
    if ([string]::IsNullOrWhiteSpace($WorktreePath)) {
        Stop-WithMessage "show-file requires -WorktreePath"
    }

    Assert-SafeRef -Value $Ref
    $resolvedPath = Resolve-ReviewWorktree -Path $WorktreePath
    $repoRelativePath = Normalize-RepoPath -Path $RepoPath
    $objectName = "${Ref}:$repoRelativePath"

    Invoke-Tool -FilePath "git" -Arguments @("-C", $resolvedPath, "-c", "core.quotePath=false", "show", $objectName) -FailureMessage "git show failed"
}

function Search-ReviewFile {
    if ([string]::IsNullOrWhiteSpace($WorktreePath)) {
        Stop-WithMessage "grep-file requires -WorktreePath"
    }

    Assert-SafeRef -Value $Ref
    Assert-RegexPattern -Value $Pattern
    Assert-FirstCount -Value $First
    $resolvedPath = Resolve-ReviewWorktree -Path $WorktreePath
    $repoRelativePath = Normalize-RepoPath -Path $RepoPath
    $objectName = "${Ref}:$repoRelativePath"
    $lines = Invoke-Tool -FilePath "git" -Arguments @("-C", $resolvedPath, "-c", "core.quotePath=false", "show", $objectName) -FailureMessage "git show failed"
    $regex = [regex]::new($Pattern)
    $matchCount = 0

    for ($index = 0; $index -lt $lines.Count; $index++) {
        $line = [string]$lines[$index]
        if ($regex.IsMatch($line)) {
            "{0}:{1}" -f ($index + 1), $line
            $matchCount++
            if (($First -gt 0) -and ($matchCount -ge $First)) {
                break
            }
        }
    }
}

function Get-ReviewFiles {
    if ([string]::IsNullOrWhiteSpace($WorktreePath)) {
        Stop-WithMessage "list-files requires -WorktreePath"
    }

    Assert-SafeRef -Value $Ref
    $resolvedPath = Resolve-ReviewWorktree -Path $WorktreePath
    $repoRelativePath = Normalize-RepoPath -Path $RepoPath -AllowEmpty

    if ($repoRelativePath -eq ".") {
        Invoke-Tool -FilePath "git" -Arguments @("-C", $resolvedPath, "-c", "core.quotePath=false", "ls-tree", "-r", "--name-only", $Ref) -FailureMessage "git ls-tree failed"
    } else {
        Invoke-Tool -FilePath "git" -Arguments @("-C", $resolvedPath, "-c", "core.quotePath=false", "ls-tree", "-r", "--name-only", $Ref, "--", $repoRelativePath) -FailureMessage "git ls-tree failed"
    }
}

function Search-ReviewTree {
    if ([string]::IsNullOrWhiteSpace($WorktreePath)) {
        Stop-WithMessage "grep-tree requires -WorktreePath"
    }

    Assert-SafeRef -Value $Ref
    Assert-RegexPattern -Value $Pattern
    Assert-FirstCount -Value $First
    $resolvedPath = Resolve-ReviewWorktree -Path $WorktreePath
    $arguments = @("-C", $resolvedPath, "-c", "core.quotePath=false", "grep", "-n", "-E", "--no-color", "-e", $Pattern, $Ref)
    if (-not [string]::IsNullOrWhiteSpace($RepoPath)) {
        $repoRelativePath = Normalize-RepoPath -Path $RepoPath -AllowEmpty
        if ($repoRelativePath -ne ".") {
            $arguments += @("--", $repoRelativePath)
        }
    }

    $result = Invoke-NativeCommand -FilePath "git" -Arguments $arguments
    if ($result.ExitCode -eq 1) {
        return
    }

    if ($result.ExitCode -ne 0) {
        $text = ($result.Output | Out-String).Trim()
        if ([string]::IsNullOrWhiteSpace($text)) {
            $text = "exit code $($result.ExitCode)"
        }
        Stop-WithMessage "git grep failed: $text"
    }

    if ($First -gt 0) {
        $result.Output | Select-Object -First $First
    } else {
        $result.Output
    }
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

    "show-file" {
        Show-ReviewFile
    }

    "grep-file" {
        Search-ReviewFile
    }

    "list-files" {
        Get-ReviewFiles
    }

    "grep-tree" {
        Search-ReviewTree
    }
}
