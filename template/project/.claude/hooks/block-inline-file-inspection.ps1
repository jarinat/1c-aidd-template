Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

[Console]::InputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

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

function Get-JsonProperty {
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$Object,

        [Parameter(Mandatory = $true)]
        [string]$Name
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

function Convert-ToolInputToText {
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$ToolInput
    )

    if ($null -eq $ToolInput) {
        return ""
    }

    if ($ToolInput -is [string]) {
        return $ToolInput
    }

    return ($ToolInput | ConvertTo-Json -Depth 50 -Compress)
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

function Test-AllowedReadOnlyGitCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command
    )

    $readOnlyGitCommandPattern = @(
        "^\s*git(\.exe)?\s+",
        "(status|diff|log|show|branch|rev-parse|merge-base|remote|ls-files|describe|name-rev|for-each-ref)",
        "(\s+[^;&|()`<>]*)?",
        "(\s*\|\s*(head|tail)(\s+-n?\s*\d+|\s+-\d+)?\s*)?$"
    ) -join ""

    return Test-Regex -Text $Command -Pattern $readOnlyGitCommandPattern
}

function Test-BslSourcePath {
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $false
    }

    $normalizedPath = $Path -replace "\\", "/"
    return Test-Regex -Text $normalizedPath -Pattern "(^|/)src/.+\.bsl$"
}

function Get-SelectedEdtMcp {
    $projectRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    $mcpConfigPath = Join-Path -Path $projectRoot -ChildPath ".mcp.json"

    if (-not (Test-Path -LiteralPath $mcpConfigPath -PathType Leaf)) {
        return [pscustomobject]@{
            Server = $null
            Error = "Project MCP configuration is missing: .mcp.json. Configure exactly one EDT MCP server: edt-companion-mcp, edt-mcp, or 1c-rsv."
        }
    }

    try {
        $mcpConfig = Get-Content -LiteralPath $mcpConfigPath -Raw | ConvertFrom-Json
    }
    catch {
        return [pscustomobject]@{
            Server = $null
            Error = "Project MCP configuration .mcp.json is not valid JSON: $($_.Exception.Message)"
        }
    }

    $servers = Get-JsonProperty -Object $mcpConfig -Name "mcpServers"
    if ($null -eq $servers) {
        return [pscustomobject]@{
            Server = $null
            Error = "Project MCP configuration .mcp.json has no mcpServers object. Configure exactly one EDT MCP server."
        }
    }

    $edtServerNames = @(
        $servers.PSObject.Properties.Name | Where-Object {
            $_ -in @("edt-companion-mcp", "edt-mcp", "1c-rsv")
        }
    )

    if ($edtServerNames.Count -ne 1) {
        $actual = if ($edtServerNames.Count -eq 0) { "none" } else { $edtServerNames -join ", " }
        return [pscustomobject]@{
            Server = $null
            Error = "Project MCP configuration must contain exactly one EDT MCP server (edt-companion-mcp, edt-mcp, 1c-rsv); found: $actual."
        }
    }

    return [pscustomobject]@{
        Server = $edtServerNames[0]
        Error = $null
    }
}

function Get-EdtMcpServerFromToolName {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ToolName
    )

    if ($ToolName -match "^mcp__edt-companion-mcp__") {
        return "edt-companion-mcp"
    }

    if ($ToolName -match "^mcp__edt-mcp__") {
        return "edt-mcp"
    }

    if ($ToolName -match "^mcp__1c-rsv__") {
        return "1c-rsv"
    }

    return $null
}

$inputJson = [Console]::In.ReadToEnd()
if ([string]::IsNullOrWhiteSpace($inputJson)) {
    exit 0
}

try {
    $payload = $inputJson | ConvertFrom-Json
}
catch {
    Write-Deny -Reason "PreToolUse hook could not parse JSON payload. Failing closed; check .claude/hooks/block-inline-file-inspection.ps1."
    exit 0
}

$toolName = [string](Get-JsonProperty -Object $payload -Name "tool_name")
$toolInput = Get-JsonProperty -Object $payload -Name "tool_input"
$inputText = Convert-ToolInputToText -ToolInput $toolInput

if ([string]::IsNullOrWhiteSpace($toolName)) {
    exit 0
}

$edtMcpServerFromTool = Get-EdtMcpServerFromToolName -ToolName $toolName
if ($null -ne $edtMcpServerFromTool) {
    $selectedEdtMcp = Get-SelectedEdtMcp
    if (-not [string]::IsNullOrWhiteSpace($selectedEdtMcp.Error)) {
        Write-Deny -Reason $selectedEdtMcp.Error
        exit 0
    }

    if ($selectedEdtMcp.Server -ne $edtMcpServerFromTool) {
        Write-Deny -Reason "EDT MCP '$edtMcpServerFromTool' is not selected for this project. .mcp.json selects '$($selectedEdtMcp.Server)'; use only mcp__$($selectedEdtMcp.Server)__* tools."
        exit 0
    }
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

$scriptWrapperReason = @"
Project scripts must be called by their canonical repo-relative wrapper from .claude/scripts.
Do not wrap them with cmd /c, cmd.exe /c, powershell -File, powershell -Command, or absolute paths.
"@.Trim()

$scriptBackslashReason = @"
Bash command calls a project script with backslashes. Use the canonical
repo-relative wrapper path with forward slashes, for example:
.claude/scripts/aidd-bootstrap-ticket.cmd <ticket>
"@.Trim()

$gitCommitReason = @"
Direct git add/git commit is blocked. Use .claude/skills/aidd-commit-block/SKILL.md
and the canonical helper: bash .claude/scripts/commit-block.sh ...
"@.Trim()

$dokTransliterationReason = @"
Latin Dok_ is blocked in 1C/YAxUnit paths and object names. Use the Cyrillic project prefix from .claude/rules/project/naming.md and .claude/skills/mpl-yaxunit/SKILL.md.
"@.Trim()

$bslFilesystemEditReason = @"
Direct filesystem Write/Edit of BSL under the project source tree is blocked. Use write_module_source of the EDT MCP selected in .mcp.json when available. Filesystem fallback needs an explicit user decision and literal tooling evidence.
"@.Trim()

if (Test-Regex -Text $inputText -Pattern "\bDok_") {
    Write-Deny -Reason $dokTransliterationReason
    exit 0
}

if ($toolName -eq "Bash") {
    $command = [string](Get-JsonProperty -Object $toolInput -Name "command")
    if ([string]::IsNullOrWhiteSpace($command)) {
        exit 0
    }

    if (Test-Regex -Text $command -Pattern '(^|[;&|()`"''\s])(\./)?\.claude\\scripts\\') {
        Write-Deny -Reason $scriptBackslashReason
        exit 0
    }

    if (Test-Regex -Text $command -Pattern "(cmd(\.exe)?\s*/c|powershell(\.exe)?\s+(-File|-Command))[\s\S]*\.claude[\\/]+scripts[\\/]") {
        Write-Deny -Reason $scriptWrapperReason
        exit 0
    }

    if (Test-Regex -Text $command -Pattern '(^|[;&|()`"''\s])git(\.exe)?\s+(add|commit)(\s|$)') {
        Write-Deny -Reason $gitCommitReason
        exit 0
    }

    if (Test-Regex -Text $command -Pattern "(^|[^\w])([A-Za-z]:\\|\\\\)") {
        Write-Deny -Reason $windowsPathReason
        exit 0
    }

    if (Test-AllowedReadOnlyGitCommand -Command $command) {
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
}

if ($toolName -match "^(Write|Edit|MultiEdit)$") {
    $filePath = [string](Get-JsonProperty -Object $toolInput -Name "file_path")
    if (Test-BslSourcePath -Path $filePath) {
        Write-Deny -Reason $bslFilesystemEditReason
        exit 0
    }
}

exit 0
