<#
.SYNOPSIS
Universal GitLab entrypoint for Claude Code sessions: reads MR threads and
pipelines, posts general notes, answers MR threads, starts inline review
threads, all through glab.

.DESCRIPTION
One approval-friendly entrypoint for GitLab operations, so that sessions stop
re-inventing inline glab pipelines, JSON parsing, UTF-8 handling and retries.

This script is NOT a glab passthrough. Every operation is an explicit,
validated subcommand. There is deliberately no "run any endpoint" command:
that would reintroduce shell escaping problems and would make the permission
rules meaningless.

Design rules. Keep them when adding commands:

  1. Read commands and write commands stay separated in help, in code, and in
     .claude/settings.json.
  2. Read commands may be allow-listed in permissions.allow by subcommand
     prefix, for example "Bash(.claude/scripts/gitlab-tools.cmd threads:*)".
  3. Write commands must stay OUT of permissions.allow, so that every
     publication to GitLab hits a permission prompt. This is the second gate
     under the skill rule "show the draft, get an explicit confirmation".
  4. NEVER add "Bash(.claude/scripts/gitlab-tools.cmd:*)" to permissions.allow.
     A wildcard over subcommands would silently grant unattended GitLab writes
     to every future session.
  5. Note bodies come from files, never from command line strings. It keeps
     Cyrillic, backticks, quotes and newlines out of shell escaping.
  6. Retry only on DNS lookup failures. They prove the request never reached
     GitLab, so a retry cannot duplicate a note. Never retry a write that may
     already have been delivered.
  7. Authentication is glab auth only. Tokens from environment variables, git
     credential manager, prompts or chat are intentionally not used.
  8. Never write @(Invoke-GlabApiJson ...) around the call itself. In Windows
     PowerShell 5.1 ConvertFrom-Json emits a JSON array as ONE object instead
     of enumerating it, so @(call) yields a single nested array element and
     every field read from [0] silently becomes empty. Assign the response to
     a variable first, then wrap it: $r = Invoke-GlabApiJson ...; $items = @($r).
  9. Endpoints with a nested payload go through "--input <file>" as raw JSON,
     not through --field. glab --field builds a flat JSON body, so a key like
     "position[new_line]" would reach GitLab as a literal key name instead of a
     nested object, and the thread would silently degrade to a plain note.

How to add a command:

  - add the name to the ValidateSet of $Command, in the read or write group;
  - add a function next to the functions of the same kind;
  - add a usage line and a short description to Show-Help;
  - if it is a read command, add its prefix to permissions.allow;
  - document the scenario in .claude/skills/gitlab-tools/SKILL.md.

Known extension points, deliberately not implemented yet:

  - creating a merge request: it is a write operation that cannot be tested
    without side effects and depends on project branch/ticket rules;
  - approving or merging: irreversible, must stay a human action in the UI.

Related:

  - .claude/scripts/gitlab-mr-review.cmd builds the read-only review context
    (worktree, diffs, snapshots). It is a different tool with a blanket
    read-only permission and must not gain write commands.

.EXAMPLE
.claude/scripts/gitlab-tools.cmd threads -MrUrl https://gitlab.example.com/group/project/-/merge_requests/123

.EXAMPLE
.claude/scripts/gitlab-tools.cmd pipeline -MrUrl https://gitlab.example.com/group/project/-/merge_requests/123

.EXAMPLE
.claude/scripts/gitlab-tools.cmd pipeline-log -MrUrl https://gitlab.example.com/group/project/-/merge_requests/123 -JobId 12345 -Tail 100

.EXAMPLE
.claude/scripts/gitlab-tools.cmd reply -MrUrl https://gitlab.example.com/group/project/-/merge_requests/123 -DiscussionId 8b171c1424ab7a8b44bcda8e62e2498d32650a44 -BodyFile reply.md

.EXAMPLE
.claude/scripts/gitlab-tools.cmd discuss -MrUrl https://gitlab.example.com/group/project/-/merge_requests/123 -Path src/cf/src/CommonModules/Module.bsl -Line 374 -BodyFile finding.md -ExpectedHeadSha 6594bf1f
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0, Mandatory = $true)]
    [ValidateSet("help", "threads", "pipeline", "pipeline-log", "note", "reply", "resolve", "discuss")]
    [string]$Command,

    [string]$MrUrl,

    [string]$DiscussionId,

    [string]$BodyFile,

    [string]$JobId,

    [int]$Tail = 200,

    [switch]$Unresolve,

    [switch]$IncludeSystem,

    [string]$Path,

    [int]$Line = 0,

    [string]$OldPath,

    [int]$OldLine = 0,

    [string]$ExpectedHeadSha
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

try {
    [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false
    $OutputEncoding = [Console]::OutputEncoding
} catch {
    # Keep the default output encoding if the host does not allow changing it.
}

function Stop-WithMessage {
    param([Parameter(Mandatory = $true)][string]$Message)

    [Console]::Error.WriteLine($Message)
    exit 2
}

function Show-Help {
    @"
Usage:
  gitlab-tools.cmd help

Read commands:
  gitlab-tools.cmd threads -MrUrl <merge-request-url> [-IncludeSystem]
  gitlab-tools.cmd pipeline -MrUrl <merge-request-url>
  gitlab-tools.cmd pipeline-log -MrUrl <merge-request-url> -JobId <job-id> [-Tail <lines>]

Write commands (never allow-listed, always ask for permission):
  gitlab-tools.cmd note -MrUrl <merge-request-url> -BodyFile <path>
  gitlab-tools.cmd reply -MrUrl <merge-request-url> -DiscussionId <id> -BodyFile <path>
  gitlab-tools.cmd resolve -MrUrl <merge-request-url> -DiscussionId <id> [-Unresolve]
  gitlab-tools.cmd discuss -MrUrl <merge-request-url> -Path <repo-relative-path> -BodyFile <path>
                           [-Line <new-line>] [-OldLine <old-line>] [-OldPath <path>]
                           [-ExpectedHeadSha <sha>]

threads:
  - prints MR discussions as JSON, human notes only
  - hides system notes such as "added 1 commit" unless -IncludeSystem is set
  - each note carries id, author, body, resolved flag, note_url and the diff
    position it was written against
  - note positions may point at an older revision: a comment survives renames
    and force pushes, so verify the current code, not the path in the note

pipeline:
  - prints the latest pipeline of the MR head with all jobs as JSON
  - failed_jobs lists job ids to pass to pipeline-log

pipeline-log:
  - prints the trace of one job as plain text
  - prints the last -Tail lines, default 200, use -Tail 0 for the full trace

reply:
  - posts one note into an existing discussion thread
  - the body is always read from -BodyFile as UTF-8, never from the command line
  - the note is published under the authenticated user account

note:
  - posts one general note to the merge request, without a diff anchor
  - the body is always read from -BodyFile as UTF-8, never from the command line
  - use it only when a review finding cannot be anchored to a changed line

resolve:
  - marks a thread resolved, or unresolved with -Unresolve

discuss:
  - starts a NEW resolvable thread anchored to a line of the MR diff
  - the body is always read from -BodyFile as UTF-8, never from the command line
  - the note is published under the authenticated user account
  - base_sha, start_sha and head_sha are read from the MR itself, never passed in
  - -Path is the repo-relative path exactly as printed by the review manifest:
    forward slashes, no drive letter, no manual decoding of Cyrillic names
  - -Line is the line number on the NEW side of the diff, as numbered in the file
    at head_sha, not the line number inside diff.patch
  - anchor rules, enforced by GitLab: an added line needs -Line, a deleted line
    needs -OldLine, an unchanged context line needs both; the line must belong to
    the diff, arbitrary lines of an untouched file cannot be commented
  - -OldPath is only needed for a renamed file, it defaults to -Path
  - -ExpectedHeadSha fails the call when the MR head moved since the review, so a
    thread cannot land on code that was never reviewed

Implementation:
  gitlab-tools.ps1 is called by the .cmd wrapper. Claude Code should use
  gitlab-tools.cmd as the external entrypoint.

Authentication:
  Uses only glab auth for GitLab API calls. Tokens from environment variables
  or git credential manager are intentionally not used.
"@
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

function Get-PropertyValue {
    param(
        [Parameter(Mandatory = $false)]$Object,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if ($null -eq $Object) {
        return $null
    }

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }

    return $property.Value
}

function Parse-MrUrl {
    param([Parameter(Mandatory = $true)][string]$Url)

    $pattern = "^https?://(?<host>[^/]+)/(?<project>.+)/-/merge_requests/(?<iid>[0-9]+)(?:[/?#].*)?$"
    $match = [regex]::Match($Url, $pattern)
    if (-not $match.Success) {
        Stop-WithMessage "Unsupported GitLab MR URL: $Url"
    }

    $projectPath = [System.Uri]::UnescapeDataString($match.Groups["project"].Value).Trim("/")

    [pscustomobject]@{
        Host = $match.Groups["host"].Value
        ProjectPath = $projectPath
        EncodedProject = [System.Uri]::EscapeDataString($projectPath)
        Iid = $match.Groups["iid"].Value
        BaseUrl = "https://$($match.Groups["host"].Value)/$projectPath/-/merge_requests/$($match.Groups["iid"].Value)"
    }
}

function Assert-DiscussionId {
    param([Parameter(Mandatory = $true)][string]$Value)

    if ($Value -notmatch "^[0-9a-fA-F]{8,64}$") {
        Stop-WithMessage "Unsupported discussion id: $Value. Expected a hex id from 'gitlab-tools.cmd threads'."
    }
}

function Assert-JobId {
    param([Parameter(Mandatory = $true)][string]$Value)

    if ($Value -notmatch "^[0-9]{1,20}$") {
        Stop-WithMessage "Unsupported job id: $Value. Expected a numeric id from 'gitlab-tools.cmd pipeline'."
    }
}

function Assert-CommitSha {
    param(
        [Parameter(Mandatory = $true)][string]$Value,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if ($Value -notmatch "^[0-9a-fA-F]{7,40}$") {
        Stop-WithMessage "Unsupported ${Name}: $Value. Expected a hex commit sha of 7 to 40 characters."
    }
}

function Assert-RepoRelativePath {
    param([Parameter(Mandatory = $true)][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value) -or $Value -match "^[A-Za-z]:" -or $Value.StartsWith("/") -or $Value.Contains("\") -or $Value -match "(^|/)\.\.?($|/)") {
        Stop-WithMessage "Unsupported path: $Value. Expected a repo-relative path with forward slashes, copied verbatim from the review manifest."
    }
}

function Test-IsDnsLookupFailure {
    param([Parameter(Mandatory = $true)][string]$Text)

    return ($Text -match "dial tcp: lookup" -and $Text -match "i/o timeout|no such host")
}

function Assert-GlabReady {
    param([Parameter(Mandatory = $true)][string]$HostName)

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
}

function Invoke-GlabApi {
    param(
        [Parameter(Mandatory = $true)][string]$HostName,
        [Parameter(Mandatory = $true)][string]$Endpoint,
        [string]$Method = "GET",
        [string[]]$ExtraArguments = @(),
        [int]$RetryCount = 2
    )

    Assert-GlabReady -HostName $HostName

    $arguments = @("api", "--hostname", $HostName, $Endpoint, "--method", $Method) + $ExtraArguments

    $attempt = 0
    while ($true) {
        $result = Invoke-NativeCommand -FilePath "glab" -Arguments $arguments
        if ($result.ExitCode -eq 0) {
            return ($result.Output | Out-String)
        }

        $text = ($result.Output | Out-String).Trim()

        # Retry only when DNS resolution failed: the request provably never
        # reached GitLab, so a retry cannot duplicate a note or a resolve.
        if ($attempt -ge $RetryCount -or -not (Test-IsDnsLookupFailure -Text $text)) {
            if ([string]::IsNullOrWhiteSpace($text)) {
                $text = "glab api failed"
            }
            Stop-WithMessage "glab API request failed: $Method $HostName/$Endpoint. Check glab auth token scopes and project access. $text"
        }

        $attempt++
        Start-Sleep -Seconds (2 * $attempt)
    }
}

function Invoke-GlabApiJson {
    param(
        [Parameter(Mandatory = $true)][string]$HostName,
        [Parameter(Mandatory = $true)][string]$Endpoint,
        [string]$Method = "GET",
        [string[]]$ExtraArguments = @()
    )

    $json = (Invoke-GlabApi -HostName $HostName -Endpoint $Endpoint -Method $Method -ExtraArguments $ExtraArguments).Trim()
    if ([string]::IsNullOrWhiteSpace($json)) {
        Stop-WithMessage "glab API returned an empty response for $HostName/$Endpoint"
    }

    try {
        return $json | ConvertFrom-Json
    } catch {
        Stop-WithMessage "glab API returned invalid JSON for $HostName/$Endpoint"
    }
}

function Assert-MrUrl {
    if ([string]::IsNullOrWhiteSpace($MrUrl)) {
        Stop-WithMessage "$Command requires -MrUrl"
    }
}

function Get-MrThreads {
    Assert-MrUrl
    $urlInfo = Parse-MrUrl -Url $MrUrl

    $endpoint = "projects/$($urlInfo.EncodedProject)/merge_requests/$($urlInfo.Iid)/discussions?per_page=100"
    $discussions = Invoke-GlabApiJson -HostName $urlInfo.Host -Endpoint $endpoint -ExtraArguments @("--paginate")

    $threads = @()
    foreach ($discussion in @($discussions)) {
        $notes = @()
        foreach ($note in @(Get-PropertyValue -Object $discussion -Name "notes")) {
            $isSystem = [bool](Get-PropertyValue -Object $note -Name "system")
            if ($isSystem -and -not $IncludeSystem) {
                continue
            }

            $position = Get-PropertyValue -Object $note -Name "position"
            $positionInfo = $null
            if ($null -ne $position) {
                $positionInfo = [pscustomobject]@{
                    new_path = Get-PropertyValue -Object $position -Name "new_path"
                    new_line = Get-PropertyValue -Object $position -Name "new_line"
                    old_path = Get-PropertyValue -Object $position -Name "old_path"
                    old_line = Get-PropertyValue -Object $position -Name "old_line"
                    head_sha = Get-PropertyValue -Object $position -Name "head_sha"
                }
            }

            $noteId = Get-PropertyValue -Object $note -Name "id"
            $notes += [pscustomobject]@{
                id = $noteId
                author = Get-PropertyValue -Object (Get-PropertyValue -Object $note -Name "author") -Name "username"
                created_at = Get-PropertyValue -Object $note -Name "created_at"
                system = $isSystem
                resolvable = Get-PropertyValue -Object $note -Name "resolvable"
                resolved = Get-PropertyValue -Object $note -Name "resolved"
                body = Get-PropertyValue -Object $note -Name "body"
                position = $positionInfo
                note_url = "$($urlInfo.BaseUrl)#note_$noteId"
            }
        }

        if ($notes.Count -eq 0) {
            continue
        }

        $threads += [pscustomobject]@{
            discussion_id = Get-PropertyValue -Object $discussion -Name "id"
            resolved = [bool](Get-PropertyValue -Object $notes[0] -Name "resolved")
            notes = $notes
        }
    }

    $unresolved = @($threads | Where-Object { -not $_.resolved })

    [pscustomobject]@{
        schema = "gitlab-tools-threads.v1"
        mr_url = $urlInfo.BaseUrl
        threads_total = $threads.Count
        threads_unresolved = $unresolved.Count
        threads = $threads
    } | ConvertTo-Json -Depth 8
}

function Get-MrPipeline {
    Assert-MrUrl
    $urlInfo = Parse-MrUrl -Url $MrUrl

    $pipelinesEndpoint = "projects/$($urlInfo.EncodedProject)/merge_requests/$($urlInfo.Iid)/pipelines?per_page=20"
    $pipelinesResponse = Invoke-GlabApiJson -HostName $urlInfo.Host -Endpoint $pipelinesEndpoint
    $pipelines = @($pipelinesResponse)
    if ($pipelines.Count -eq 0) {
        Stop-WithMessage "No pipelines found for $($urlInfo.BaseUrl)"
    }

    $pipeline = $pipelines[0]
    $pipelineId = Get-PropertyValue -Object $pipeline -Name "id"

    $jobsEndpoint = "projects/$($urlInfo.EncodedProject)/pipelines/$pipelineId/jobs?per_page=100"
    $jobsResponse = Invoke-GlabApiJson -HostName $urlInfo.Host -Endpoint $jobsEndpoint -ExtraArguments @("--paginate")
    $jobs = @($jobsResponse)

    $jobInfos = @()
    foreach ($job in $jobs) {
        $jobInfos += [pscustomobject]@{
            id = Get-PropertyValue -Object $job -Name "id"
            name = Get-PropertyValue -Object $job -Name "name"
            stage = Get-PropertyValue -Object $job -Name "stage"
            status = Get-PropertyValue -Object $job -Name "status"
            allow_failure = Get-PropertyValue -Object $job -Name "allow_failure"
            web_url = Get-PropertyValue -Object $job -Name "web_url"
        }
    }

    $failed = @($jobInfos | Where-Object { $_.status -eq "failed" })

    [pscustomobject]@{
        schema = "gitlab-tools-pipeline.v1"
        mr_url = $urlInfo.BaseUrl
        pipeline = [pscustomobject]@{
            id = $pipelineId
            status = Get-PropertyValue -Object $pipeline -Name "status"
            ref = Get-PropertyValue -Object $pipeline -Name "ref"
            sha = Get-PropertyValue -Object $pipeline -Name "sha"
            web_url = Get-PropertyValue -Object $pipeline -Name "web_url"
        }
        jobs_total = $jobInfos.Count
        failed_jobs = $failed
        jobs = $jobInfos
    } | ConvertTo-Json -Depth 8
}

function Get-MrPipelineLog {
    Assert-MrUrl
    if ([string]::IsNullOrWhiteSpace($JobId)) {
        Stop-WithMessage "pipeline-log requires -JobId. Take it from 'gitlab-tools.cmd pipeline'."
    }
    Assert-JobId -Value $JobId

    $urlInfo = Parse-MrUrl -Url $MrUrl
    $endpoint = "projects/$($urlInfo.EncodedProject)/jobs/$JobId/trace"
    $trace = Invoke-GlabApi -HostName $urlInfo.Host -Endpoint $endpoint

    if ([string]::IsNullOrWhiteSpace($trace)) {
        Stop-WithMessage "Job $JobId has an empty trace. The job may not have started, or the trace may be expired."
    }

    $lines = $trace -split "`r?`n"
    if ($Tail -gt 0 -and $lines.Count -gt $Tail) {
        $lines = $lines[($lines.Count - $Tail)..($lines.Count - 1)]
        [Console]::Error.WriteLine("Showing the last $Tail lines of job $JobId. Use -Tail 0 for the full trace.")
    }

    $lines -join [Environment]::NewLine
}

function Add-MrReply {
    Assert-MrUrl
    if ([string]::IsNullOrWhiteSpace($DiscussionId)) {
        Stop-WithMessage "reply requires -DiscussionId. Take it from 'gitlab-tools.cmd threads'."
    }
    if ([string]::IsNullOrWhiteSpace($BodyFile)) {
        Stop-WithMessage "reply requires -BodyFile. Write the note text to a file first."
    }

    Assert-DiscussionId -Value $DiscussionId

    if (-not (Test-Path -LiteralPath $BodyFile -PathType Leaf)) {
        Stop-WithMessage "Body file not found: $BodyFile"
    }

    $bodyPath = (Resolve-Path -LiteralPath $BodyFile).Path
    $body = [System.IO.File]::ReadAllText($bodyPath, (New-Object System.Text.UTF8Encoding $false))
    if ([string]::IsNullOrWhiteSpace($body)) {
        Stop-WithMessage "Body file is empty: $BodyFile"
    }

    # glab --field converts bare literals to JSON types, which would send a note
    # body of the wrong type. Real replies are prose, so reject the degenerate case.
    if ($body.Trim() -match "^(true|false|null|-?[0-9]+(\.[0-9]+)?)$") {
        Stop-WithMessage "Body file contains a bare JSON literal: $($body.Trim()). Write the reply as text."
    }

    $urlInfo = Parse-MrUrl -Url $MrUrl
    $endpoint = "projects/$($urlInfo.EncodedProject)/merge_requests/$($urlInfo.Iid)/discussions/$DiscussionId/notes"
    $note = Invoke-GlabApiJson -HostName $urlInfo.Host -Endpoint $endpoint -Method "POST" -ExtraArguments @("--field", "body=@$bodyPath")

    $noteId = Get-PropertyValue -Object $note -Name "id"

    [pscustomobject]@{
        schema = "gitlab-tools-reply.v1"
        mr_url = $urlInfo.BaseUrl
        discussion_id = $DiscussionId
        note_id = $noteId
        note_url = "$($urlInfo.BaseUrl)#note_$noteId"
        author = Get-PropertyValue -Object (Get-PropertyValue -Object $note -Name "author") -Name "username"
        created_at = Get-PropertyValue -Object $note -Name "created_at"
    } | ConvertTo-Json -Depth 4
}

function Add-MrNote {
    Assert-MrUrl
    if ([string]::IsNullOrWhiteSpace($BodyFile)) {
        Stop-WithMessage "note requires -BodyFile. Write the note text to a file first."
    }

    if (-not (Test-Path -LiteralPath $BodyFile -PathType Leaf)) {
        Stop-WithMessage "Body file not found: $BodyFile"
    }

    $bodyPath = (Resolve-Path -LiteralPath $BodyFile).Path
    $body = [System.IO.File]::ReadAllText($bodyPath, (New-Object System.Text.UTF8Encoding $false))
    if ([string]::IsNullOrWhiteSpace($body)) {
        Stop-WithMessage "Body file is empty: $BodyFile"
    }

    if ($body.Trim() -match "^(true|false|null|-?[0-9]+(\.[0-9]+)?)$") {
        Stop-WithMessage "Body file contains a bare JSON literal: $($body.Trim()). Write the note as text."
    }

    $urlInfo = Parse-MrUrl -Url $MrUrl
    $endpoint = "projects/$($urlInfo.EncodedProject)/merge_requests/$($urlInfo.Iid)/notes"
    $note = Invoke-GlabApiJson -HostName $urlInfo.Host -Endpoint $endpoint -Method "POST" -ExtraArguments @("--field", "body=@$bodyPath")
    $noteId = Get-PropertyValue -Object $note -Name "id"

    [pscustomobject]@{
        schema = "gitlab-tools-note.v1"
        mr_url = $urlInfo.BaseUrl
        note_id = $noteId
        note_url = "$($urlInfo.BaseUrl)#note_$noteId"
        author = Get-PropertyValue -Object (Get-PropertyValue -Object $note -Name "author") -Name "username"
        created_at = Get-PropertyValue -Object $note -Name "created_at"
    } | ConvertTo-Json -Depth 4
}

function Add-MrDiscussion {
    Assert-MrUrl
    if ([string]::IsNullOrWhiteSpace($Path)) {
        Stop-WithMessage "discuss requires -Path. Copy the repo-relative path verbatim from the review manifest."
    }
    if ([string]::IsNullOrWhiteSpace($BodyFile)) {
        Stop-WithMessage "discuss requires -BodyFile. Write the note text to a file first."
    }

    Assert-RepoRelativePath -Value $Path

    if ($Line -lt 0 -or $OldLine -lt 0) {
        Stop-WithMessage "Line numbers must be positive: -Line $Line, -OldLine $OldLine"
    }
    if ($Line -eq 0 -and $OldLine -eq 0) {
        Stop-WithMessage "discuss requires -Line for an added line, -OldLine for a deleted line, or both for an unchanged context line."
    }

    $oldPathValue = $OldPath
    if ([string]::IsNullOrWhiteSpace($oldPathValue)) {
        $oldPathValue = $Path
    } else {
        Assert-RepoRelativePath -Value $oldPathValue
    }

    if (-not (Test-Path -LiteralPath $BodyFile -PathType Leaf)) {
        Stop-WithMessage "Body file not found: $BodyFile"
    }

    $bodyPath = (Resolve-Path -LiteralPath $BodyFile).Path
    $body = [System.IO.File]::ReadAllText($bodyPath, (New-Object System.Text.UTF8Encoding $false))
    if ([string]::IsNullOrWhiteSpace($body)) {
        Stop-WithMessage "Body file is empty: $BodyFile"
    }

    $urlInfo = Parse-MrUrl -Url $MrUrl

    $mrEndpoint = "projects/$($urlInfo.EncodedProject)/merge_requests/$($urlInfo.Iid)"
    $mr = Invoke-GlabApiJson -HostName $urlInfo.Host -Endpoint $mrEndpoint
    $diffRefs = Get-PropertyValue -Object $mr -Name "diff_refs"
    if ($null -eq $diffRefs) {
        Stop-WithMessage "MR $($urlInfo.BaseUrl) has no diff_refs. GitLab has not finished preparing the diff, retry later."
    }

    $baseSha = Get-PropertyValue -Object $diffRefs -Name "base_sha"
    $startSha = Get-PropertyValue -Object $diffRefs -Name "start_sha"
    $headSha = Get-PropertyValue -Object $diffRefs -Name "head_sha"
    if ([string]::IsNullOrWhiteSpace($baseSha) -or [string]::IsNullOrWhiteSpace($startSha) -or [string]::IsNullOrWhiteSpace($headSha)) {
        Stop-WithMessage "MR $($urlInfo.BaseUrl) has incomplete diff_refs. GitLab has not finished preparing the diff, retry later."
    }

    # A diff thread is bound to the revision it was written against. If the head
    # moved after the review, the anchor would land on unreviewed code.
    if (-not [string]::IsNullOrWhiteSpace($ExpectedHeadSha)) {
        Assert-CommitSha -Value $ExpectedHeadSha -Name "expected head sha"
        if (-not $headSha.StartsWith($ExpectedHeadSha, [System.StringComparison]::OrdinalIgnoreCase)) {
            Stop-WithMessage "MR head moved: reviewed $ExpectedHeadSha, current diff_refs.head_sha is $headSha. Re-run the review against the new head before publishing."
        }
    }

    $position = [ordered]@{
        base_sha = $baseSha
        start_sha = $startSha
        head_sha = $headSha
        position_type = "text"
        new_path = $Path
        old_path = $oldPathValue
    }
    if ($Line -gt 0) {
        $position["new_line"] = $Line
    }
    if ($OldLine -gt 0) {
        $position["old_line"] = $OldLine
    }

    $payload = [ordered]@{
        body = $body
        position = $position
    }

    $payloadPath = Join-Path ([System.IO.Path]::GetTempPath()) ("gitlab-tools-discuss-" + [System.Guid]::NewGuid().ToString("N") + ".json")
    $payloadJson = $payload | ConvertTo-Json -Depth 5 -Compress
    [System.IO.File]::WriteAllText($payloadPath, $payloadJson, (New-Object System.Text.UTF8Encoding $false))

    try {
        $endpoint = "projects/$($urlInfo.EncodedProject)/merge_requests/$($urlInfo.Iid)/discussions"
        $discussion = Invoke-GlabApiJson -HostName $urlInfo.Host -Endpoint $endpoint -Method "POST" -ExtraArguments @("--input", $payloadPath, "--header", "Content-Type: application/json")
    } finally {
        Remove-Item -LiteralPath $payloadPath -Force -ErrorAction SilentlyContinue
    }

    $discussionId = Get-PropertyValue -Object $discussion -Name "id"
    $notesResponse = Get-PropertyValue -Object $discussion -Name "notes"
    $notes = @($notesResponse)
    $noteId = $null
    if ($notes.Count -gt 0) {
        $noteId = Get-PropertyValue -Object $notes[0] -Name "id"
    }

    [pscustomobject]@{
        schema = "gitlab-tools-discuss.v1"
        mr_url = $urlInfo.BaseUrl
        discussion_id = $discussionId
        note_id = $noteId
        note_url = "$($urlInfo.BaseUrl)#note_$noteId"
        head_sha = $headSha
        position = [pscustomobject]@{
            new_path = $Path
            new_line = $(if ($Line -gt 0) { $Line } else { $null })
            old_path = $oldPathValue
            old_line = $(if ($OldLine -gt 0) { $OldLine } else { $null })
        }
    } | ConvertTo-Json -Depth 4
}

function Set-MrThreadResolved {
    Assert-MrUrl
    if ([string]::IsNullOrWhiteSpace($DiscussionId)) {
        Stop-WithMessage "resolve requires -DiscussionId. Take it from 'gitlab-tools.cmd threads'."
    }

    Assert-DiscussionId -Value $DiscussionId

    $resolved = if ($Unresolve) { "false" } else { "true" }
    $urlInfo = Parse-MrUrl -Url $MrUrl
    $endpoint = "projects/$($urlInfo.EncodedProject)/merge_requests/$($urlInfo.Iid)/discussions/$DiscussionId"
    $discussion = Invoke-GlabApiJson -HostName $urlInfo.Host -Endpoint $endpoint -Method "PUT" -ExtraArguments @("--field", "resolved=$resolved")

    [pscustomobject]@{
        schema = "gitlab-tools-resolve.v1"
        mr_url = $urlInfo.BaseUrl
        discussion_id = Get-PropertyValue -Object $discussion -Name "id"
        resolved = ($resolved -eq "true")
    } | ConvertTo-Json -Depth 4
}

switch ($Command) {
    "help" {
        Show-Help
    }

    "threads" {
        Get-MrThreads
    }

    "pipeline" {
        Get-MrPipeline
    }

    "pipeline-log" {
        Get-MrPipelineLog
    }

    "reply" {
        Add-MrReply
    }

    "note" {
        Add-MrNote
    }

    "discuss" {
        Add-MrDiscussion
    }

    "resolve" {
        Set-MrThreadResolved
    }

    default {
        Stop-WithMessage "Unknown command: $Command"
    }
}
