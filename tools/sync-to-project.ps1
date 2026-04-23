<#
.SYNOPSIS
Copies shared AIDD template files to one target project.

.DESCRIPTION
Synchronizes only files that exist in template/project under the shared
Claude Code runtime paths. Project-local files in the same target directories
are not changed or removed.

Run without -Apply to preview Add/Update/Unchanged operations.

.EXAMPLE
tools/sync-to-project.ps1 -ProjectPath C:/work/project

.EXAMPLE
tools/sync-to-project.ps1 -ProjectPath C:/work/project -Apply
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
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
        [string]$TargetPath
    )

    if (-not (Test-Path -LiteralPath $TargetPath -PathType Leaf)) {
        return "Add"
    }

    $sourceHash = (Get-FileHash -LiteralPath $SourcePath -Algorithm SHA256).Hash
    $targetHash = (Get-FileHash -LiteralPath $TargetPath -Algorithm SHA256).Hash

    if ($sourceHash -eq $targetHash) {
        return "Unchanged"
    }

    return "Update"
}

$repoRoot = Resolve-Directory -Path (Join-Path -Path $PSScriptRoot -ChildPath "..") -Name "Repository root"
$templateProject = Resolve-Directory -Path (Join-Path -Path $repoRoot -ChildPath "template/project") -Name "Template project"
$targetProject = Resolve-Directory -Path $ProjectPath -Name "Target project"

$syncRoots = @(
    ".claude/CLAUDE.md",
    ".claude/agents",
    ".claude/skills",
    ".claude/rules/core",
    ".claude/scripts"
)

$sourceFiles = New-Object System.Collections.Generic.List[System.IO.FileInfo]

foreach ($syncRoot in $syncRoots) {
    $sourcePath = Join-TemplatePath -Root $templateProject -RelativePath $syncRoot

    if (Test-Path -LiteralPath $sourcePath -PathType Leaf) {
        $sourceFiles.Add((Get-Item -LiteralPath $sourcePath))
        continue
    }

    if (Test-Path -LiteralPath $sourcePath -PathType Container) {
        foreach ($file in Get-ChildItem -LiteralPath $sourcePath -Recurse -File) {
            $sourceFiles.Add($file)
        }
        continue
    }

    throw "Template sync root does not exist: $syncRoot"
}

$operations = foreach ($sourceFile in $sourceFiles) {
    $relativePath = Get-RelativePath -Root $templateProject -FullPath $sourceFile.FullName
    $targetPath = Join-TemplatePath -Root $targetProject -RelativePath $relativePath
    $status = Get-FileStatus -SourcePath $sourceFile.FullName -TargetPath $targetPath

    [pscustomobject]@{
        Status = $status
        Path = ($relativePath -replace "\\", "/")
        SourcePath = $sourceFile.FullName
        TargetPath = $targetPath
    }
}

$addCount = @($operations | Where-Object { $_.Status -eq "Add" }).Count
$updateCount = @($operations | Where-Object { $_.Status -eq "Update" }).Count
$unchangedCount = @($operations | Where-Object { $_.Status -eq "Unchanged" }).Count

Write-Host "Template: $templateProject"
Write-Host "Target:   $targetProject"
Write-Host "Mode:     $(if ($Apply) { "apply" } else { "dry-run" })"
Write-Host ""
Write-Host "Summary: Add=$addCount Update=$updateCount Unchanged=$unchangedCount Remove=0"
Write-Host ""

foreach ($operation in ($operations | Sort-Object Path)) {
    if (($operation.Status -eq "Unchanged") -and (-not $ShowUnchanged)) {
        continue
    }

    Write-Host ("{0,-9} {1}" -f $operation.Status, $operation.Path)
}

if (-not $Apply) {
    Write-Host ""
    Write-Host "Dry-run only. Re-run with -Apply to copy Add/Update files."
    exit 0
}

foreach ($operation in ($operations | Where-Object { $_.Status -ne "Unchanged" })) {
    $targetDirectory = Split-Path -Path $operation.TargetPath -Parent

    if (-not (Test-Path -LiteralPath $targetDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $targetDirectory -Force | Out-Null
    }

    Copy-Item -LiteralPath $operation.SourcePath -Destination $operation.TargetPath -Force
}

Write-Host ""
Write-Host "Sync complete."
