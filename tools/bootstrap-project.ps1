<#
.SYNOPSIS
Bootstraps local AIDD/Codex/Claude Code files in one 1C/EDT project.

.DESCRIPTION
Installs the reusable runtime layer from template/project and creates missing
local project scaffolding without overwriting project-specific rules.

Run without -Apply to preview operations.

This script does not edit Git ignore/exclude files, build external indexes, or
run EDT actions.

.EXAMPLE
tools/bootstrap-project.ps1 -Project WMS

.EXAMPLE
tools/bootstrap-project.ps1 -Project WMS -Apply

.EXAMPLE
tools/bootstrap-project.ps1 -ProjectPath C:/work/project -Apply
#>
[CmdletBinding(DefaultParameterSetName = "ByProject")]
param(
    [Parameter(Mandatory = $true, ParameterSetName = "ByProject")]
    [Alias("ProjectName")]
    [string]$Project,

    [Parameter(Mandatory = $true, ParameterSetName = "ByPath")]
    [string]$ProjectPath,

    [switch]$Apply,

    [switch]$ShowUnchanged
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-Directory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "$Name directory does not exist: $Path"
    }

    return (Resolve-Path -LiteralPath $Path).Path
}

function Join-TemplatePath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,

        [Parameter(Mandatory = $true)]
        [string]$RelativePath
    )

    $result = $Root
    foreach ($part in ($RelativePath -split "[/\\]")) {
        if ($part.Length -gt 0) {
            $result = Join-Path -Path $result -ChildPath $part
        }
    }

    return $result
}

function Get-RelativePath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,

        [Parameter(Mandatory = $true)]
        [string]$FullPath
    )

    $rootWithSeparator = $Root.TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    ) + [System.IO.Path]::DirectorySeparatorChar

    if (-not $FullPath.StartsWith($rootWithSeparator, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Path is outside root. Root: $Root Path: $FullPath"
    }

    return $FullPath.Substring($rootWithSeparator.Length)
}

function Get-FileStatus {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,

        [Parameter(Mandatory = $true)]
        [string]$TargetPath,

        [Parameter(Mandatory = $true)]
        [ValidateSet("Overwrite", "CreateIfMissing")]
        [string]$Mode
    )

    if (-not (Test-Path -LiteralPath $TargetPath -PathType Leaf)) {
        return "Add"
    }

    $sourceHash = (Get-FileHash -LiteralPath $SourcePath -Algorithm SHA256).Hash
    $targetHash = (Get-FileHash -LiteralPath $TargetPath -Algorithm SHA256).Hash

    if ($sourceHash -eq $targetHash) {
        return "Unchanged"
    }

    if ($Mode -eq "CreateIfMissing") {
        return "Exists"
    }

    return "Update"
}

function Get-TemplateFiles {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TemplateRoot,

        [Parameter(Mandatory = $true)]
        [string[]]$Roots,

        [Parameter(Mandatory = $true)]
        [ValidateSet("Overwrite", "CreateIfMissing")]
        [string]$Mode
    )

    foreach ($root in $Roots) {
        $sourcePath = Join-TemplatePath -Root $TemplateRoot -RelativePath $root

        if (Test-Path -LiteralPath $sourcePath -PathType Leaf) {
            [pscustomobject]@{
                SourcePath = (Get-Item -LiteralPath $sourcePath).FullName
                RelativePath = $root
                Mode = $Mode
                GeneratedContent = $null
            }
            continue
        }

        if (Test-Path -LiteralPath $sourcePath -PathType Container) {
            foreach ($file in Get-ChildItem -LiteralPath $sourcePath -Recurse -File -Force) {
                [pscustomobject]@{
                    SourcePath = $file.FullName
                    RelativePath = Get-RelativePath -Root $TemplateRoot -FullPath $file.FullName
                    Mode = $Mode
                    GeneratedContent = $null
                }
            }
            continue
        }

        throw "Template bootstrap root does not exist: $root"
    }
}

function Get-ObsoleteTargetFiles {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetRoot,

        [Parameter(Mandatory = $true)]
        [string[]]$Roots
    )

    foreach ($root in $Roots) {
        $targetPath = Join-TemplatePath -Root $TargetRoot -RelativePath $root

        if (Test-Path -LiteralPath $targetPath) {
            [pscustomobject]@{
                SourcePath = $null
                RelativePath = $root
                Mode = "RemoveObsolete"
                GeneratedContent = $null
                TargetPath = $targetPath
            }
        }
    }
}

function Resolve-ProjectPathFromConfig {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $configPath = Join-Path -Path $RepoRoot -ChildPath "config/projects.local.json"
    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
        throw "Local project config does not exist: $configPath"
    }

    $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
    $matches = @($config.projects | Where-Object { $_.name -eq $Name })

    if ($matches.Count -eq 0) {
        throw "Project is not found in config/projects.local.json: $Name"
    }

    if ($matches.Count -gt 1) {
        throw "Project name is ambiguous in config/projects.local.json: $Name"
    }

    $projectInfo = $matches[0]
    if (($null -ne $projectInfo.enabled) -and (-not [bool]$projectInfo.enabled)) {
        throw "Project is disabled in config/projects.local.json: $Name"
    }

    return $projectInfo.path
}

$repoRoot = Resolve-Directory -Path (Join-Path -Path $PSScriptRoot -ChildPath "..") -Name "Repository root"
$templateProject = Resolve-Directory -Path (Join-Path -Path $repoRoot -ChildPath "template/project") -Name "Template project"

if ($PSCmdlet.ParameterSetName -eq "ByProject") {
    $ProjectPath = Resolve-ProjectPathFromConfig -RepoRoot $repoRoot -Name $Project
}

$targetProject = Resolve-Directory -Path $ProjectPath -Name "Target project"

$overwriteRoots = @(
    ".claude/CLAUDE.md",
    ".claude/settings.json",
    ".claude/agents",
    ".claude/hooks",
    ".claude/skills",
    ".claude/rules/core",
    ".claude/scripts",
    ".claude/docs"
)

$createIfMissingRoots = @(
    "AGENTS.md",
    ".claude/rules/project",
    ".claude/rules/paths",
    "aidd"
)

$removeObsoleteRoots = @(
    ".claude/skills/rlm-tools-bsl"
)

$sourceFiles = @()
$sourceFiles += Get-TemplateFiles -TemplateRoot $templateProject -Roots $overwriteRoots -Mode "Overwrite"
$sourceFiles += Get-TemplateFiles -TemplateRoot $templateProject -Roots $createIfMissingRoots -Mode "CreateIfMissing"
$sourceFiles = @($sourceFiles | Where-Object {
    ($_.RelativePath -replace "\\", "/") -ne ".claude/rules/paths/source-example.md"
})
$sourceFiles += [pscustomobject]@{
    SourcePath = $null
    RelativePath = "aidd/docs/.active_ticket"
    Mode = "CreateIfMissing"
    GeneratedContent = ""
}
$sourceFiles += Get-ObsoleteTargetFiles -TargetRoot $targetProject -Roots $removeObsoleteRoots

$operations = foreach ($sourceFile in $sourceFiles) {
    $targetPath = Join-TemplatePath -Root $targetProject -RelativePath $sourceFile.RelativePath

    if ($sourceFile.Mode -eq "RemoveObsolete") {
        $status = "Remove"
    }
    elseif ($null -ne $sourceFile.GeneratedContent) {
        $status = if (Test-Path -LiteralPath $targetPath -PathType Leaf) { "Exists" } else { "Add" }
    }
    else {
        $status = Get-FileStatus -SourcePath $sourceFile.SourcePath -TargetPath $targetPath -Mode $sourceFile.Mode
    }

    [pscustomobject]@{
        Status = $status
        Mode = $sourceFile.Mode
        Path = ($sourceFile.RelativePath -replace "\\", "/")
        SourcePath = $sourceFile.SourcePath
        TargetPath = $targetPath
        GeneratedContent = $sourceFile.GeneratedContent
    }
}

$addCount = @($operations | Where-Object { $_.Status -eq "Add" }).Count
$updateCount = @($operations | Where-Object { $_.Status -eq "Update" }).Count
$unchangedCount = @($operations | Where-Object { $_.Status -eq "Unchanged" }).Count
$existsCount = @($operations | Where-Object { $_.Status -eq "Exists" }).Count
$removeCount = @($operations | Where-Object { $_.Status -eq "Remove" }).Count

Write-Host "Template: $templateProject"
Write-Host "Target:   $targetProject"
Write-Host "Mode:     $(if ($Apply) { "apply" } else { "dry-run" })"
Write-Host ""
Write-Host "Summary: Add=$addCount Update=$updateCount Unchanged=$unchangedCount Exists=$existsCount Remove=$removeCount"
Write-Host ""

foreach ($operation in ($operations | Sort-Object Path)) {
    if (($operation.Status -eq "Unchanged") -and (-not $ShowUnchanged)) {
        continue
    }

    Write-Host ("{0,-9} {1,-15} {2}" -f $operation.Status, $operation.Mode, $operation.Path)
}

if (-not $Apply) {
    Write-Host ""
    Write-Host "Dry-run only. Re-run with -Apply to copy Add/Update files and create missing local scaffold."
    exit 0
}

foreach ($operation in ($operations | Where-Object { $_.Status -eq "Remove" })) {
    $resolvedTargetPath = (Resolve-Path -LiteralPath $operation.TargetPath).Path
    [void](Get-RelativePath -Root $targetProject -FullPath $resolvedTargetPath)
    Remove-Item -LiteralPath $resolvedTargetPath -Recurse -Force
}

foreach ($operation in ($operations | Where-Object { $_.Status -in @("Add", "Update") })) {
    $targetDirectory = Split-Path -Path $operation.TargetPath -Parent

    if (-not (Test-Path -LiteralPath $targetDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $targetDirectory -Force | Out-Null
    }

    if ($null -ne $operation.GeneratedContent) {
        Set-Content -LiteralPath $operation.TargetPath -Value $operation.GeneratedContent -NoNewline
        continue
    }

    Copy-Item -LiteralPath $operation.SourcePath -Destination $operation.TargetPath -Force
}

Write-Host ""
Write-Host "Bootstrap complete."
Write-Host ""
Write-Host "Next step inside target project:"
Write-Host "  Ask Codex to run project onboarding by .claude/docs/onboarding-project.md"
Write-Host "  Or ask Claude Code to use the project-onboarding skill."
