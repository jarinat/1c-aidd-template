<#
.SYNOPSIS
Universal GitLab entrypoint for Claude Code sessions: reads MR threads and
pipelines, answers MR threads, all through glab.

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
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0, Mandatory = $true)]
    [ValidateSet("help", "threads", "pipeline", "pipeline-log", "reply", "resolve")]
    [string]$Command,

    [string]$MrUrl,

    [string]$DiscussionId,

    [string]$BodyFile,

    [string]$JobId,

    [int]$Tail = 200,

    [switch]$Unresolve,

    [switch]$IncludeSystem
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
  gitlab-tools.cmd reply -MrUrl <merge-request-url> -DiscussionId <id> -BodyFile <path>
  gitlab-tools.cmd resolve -MrUrl <merge-request-url> -DiscussionId <id> [-Unresolve]

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

resolve:
  - marks a thread resolved, or unresolved with -Unresolve

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

    "resolve" {
        Set-MrThreadResolved
    }

    default {
        Stop-WithMessage "Unknown command: $Command"
    }
}
