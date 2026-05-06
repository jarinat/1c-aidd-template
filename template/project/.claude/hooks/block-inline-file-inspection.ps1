Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Deny {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Reason
    )

    $output = [ordered]@{
        hookSpecificOutput = [ordered]@{
            hookEventName = "PreToolUse"
            permissionDecision = "deny"
            permissionDecisionReason = $Reason
        }
    }

    $output | ConvertTo-Json -Depth 5 -Compress
}

function Test-Regex {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text,

        [Parameter(Mandatory = $true)]
        [string]$Pattern
    )

    return [regex]::IsMatch($Text, $Pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
}

$inputJson = [Console]::In.ReadToEnd()
if ([string]::IsNullOrWhiteSpace($inputJson)) {
    exit 0
}

try {
    $payload = $inputJson | ConvertFrom-Json
}
catch {
    exit 0
}

if ($payload.tool_name -ne "Bash") {
    exit 0
}

$command = [string]$payload.tool_input.command
if ([string]::IsNullOrWhiteSpace($command)) {
    exit 0
}

$denyReason = @"
Inline shell command looks like file inspection and was blocked by the project hook.
Use Read/Glob/Grep/MCP tools or a documented helper from .claude/scripts.
Source of truth: .claude/rules/core/tool-usage.md.
"@.Trim()

$windowsPathReason = @"
Bash command uses an absolute Windows path with backslashes. This often causes
permission prompts and escaping errors. Use repo-relative paths with / or
structured Read/Glob/Grep/MCP tools according to .claude/rules/core/tool-usage.md.
"@.Trim()

if (Test-Regex -Text $command -Pattern "(^|[^\w])([A-Za-z]:\\|\\\\)") {
    Write-Deny -Reason $windowsPathReason
    exit 0
}

$inspectionCommandPattern = @(
    "(^|[;&|()]|\s)(ls|dir|gci|Get-ChildItem|Test-Path|Get-Content|gc|type|cat|head|tail|grep|Select-String|sls|sed|awk|findstr)(\s|$)",
    "(^|[;&|()]|\s)rg(\s|$)",
    "(^|[;&|()]|\s)(python|python3|py)(\.exe)?\s+-c(\s|$)"
) -join "|"

if (Test-Regex -Text $command -Pattern $inspectionCommandPattern) {
    Write-Deny -Reason $denyReason
    exit 0
}

exit 0
