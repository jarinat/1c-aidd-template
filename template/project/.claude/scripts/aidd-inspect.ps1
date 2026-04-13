[CmdletBinding()]
param(
    [Parameter(Position = 0, Mandatory = $true)]
    [ValidateSet("help", "list", "read", "find-files", "grep", "changed-files")]
    [string]$Command,

    [Parameter(Position = 1, ValueFromRemainingArguments = $true)]
    [string[]]$Args
)

$ErrorActionPreference = "Stop"

try {
    [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false
    $OutputEncoding = [Console]::OutputEncoding
} catch {
    # Keep the default output encoding if the host does not allow changing it.
}

$ProjectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$ProjectRootFull = [System.IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\', '/')

function Stop-WithMessage {
    param([Parameter(Mandatory = $true)][string]$Message)

    Write-Error $Message
    exit 2
}

function Get-RepoPath {
    param(
        [string]$RelativePath = ".",
        [bool]$MustExist = $true
    )

    if ([string]::IsNullOrWhiteSpace($RelativePath)) {
        $RelativePath = "."
    }

    if ([System.IO.Path]::IsPathRooted($RelativePath)) {
        Stop-WithMessage "Path must be relative to repository root: $RelativePath"
    }

    $FullPath = [System.IO.Path]::GetFullPath((Join-Path $ProjectRootFull $RelativePath))
    $Comparison = [System.StringComparison]::OrdinalIgnoreCase
    $InsideRoot = $FullPath.Equals($ProjectRootFull, $Comparison) -or
        $FullPath.StartsWith($ProjectRootFull + [System.IO.Path]::DirectorySeparatorChar, $Comparison) -or
        $FullPath.StartsWith($ProjectRootFull + [System.IO.Path]::AltDirectorySeparatorChar, $Comparison)

    if (-not $InsideRoot) {
        Stop-WithMessage "Path leaves repository root: $RelativePath"
    }

    if ($MustExist -and -not (Test-Path -LiteralPath $FullPath)) {
        Stop-WithMessage "Path does not exist: $RelativePath"
    }

    return $FullPath
}

function ConvertTo-RepoRelative {
    param([Parameter(Mandatory = $true)][string]$Path)

    $FullPath = [System.IO.Path]::GetFullPath($Path)
    if ($FullPath.Equals($ProjectRootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
        return "."
    }

    return $FullPath.Substring($ProjectRootFull.Length).TrimStart('\', '/') -replace "\\", "/"
}

function Get-RepoFiles {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [string]$Filter = "*"
    )

    if (Test-Path -LiteralPath $Root -PathType Leaf) {
        return @(Get-Item -LiteralPath $Root)
    }

    return @(Get-ChildItem -LiteralPath $Root -Recurse -File -Filter $Filter -Force |
        Where-Object {
            $Relative = ConvertTo-RepoRelative $_.FullName
            $Relative -notlike ".git/*"
        })
}

function Show-Help {
    @"
Usage:
  aidd-inspect.ps1 help
  aidd-inspect.ps1 list <repo-relative-path>
  aidd-inspect.ps1 read <repo-relative-file> [max-lines]
  aidd-inspect.ps1 find-files <repo-relative-path> <file-glob>
  aidd-inspect.ps1 grep <repo-relative-path> <regex> [file-glob]
  aidd-inspect.ps1 changed-files

Examples:
  powershell -NoProfile -ExecutionPolicy Bypass -File .claude/scripts/aidd-inspect.ps1 list src
  powershell -NoProfile -ExecutionPolicy Bypass -File .claude/scripts/aidd-inspect.ps1 find-files src *.rights
  powershell -NoProfile -ExecutionPolicy Bypass -File .claude/scripts/aidd-inspect.ps1 grep src "OldName|NewName" *.bsl
"@
}

switch ($Command) {
    "help" {
        Show-Help
    }

    "list" {
        $PathArg = if ($Args.Count -ge 1) { $Args[0] } else { "." }
        $Target = Get-RepoPath $PathArg

        Get-ChildItem -LiteralPath $Target -Force |
            Sort-Object -Property @{ Expression = "PSIsContainer"; Descending = $true }, Name |
            ForEach-Object {
                $Kind = if ($_.PSIsContainer) { "DIR " } else { "FILE" }
                "{0} {1}" -f $Kind, (ConvertTo-RepoRelative $_.FullName)
            }
    }

    "read" {
        if ($Args.Count -lt 1) {
            Stop-WithMessage "read requires <repo-relative-file>"
        }

        $Target = Get-RepoPath $Args[0]
        if (-not (Test-Path -LiteralPath $Target -PathType Leaf)) {
            Stop-WithMessage "read target must be a file: $($Args[0])"
        }

        $MaxLines = 400
        if ($Args.Count -ge 2 -and -not [int]::TryParse($Args[1], [ref]$MaxLines)) {
            Stop-WithMessage "max-lines must be an integer"
        }
        if ($MaxLines -le 0) {
            Stop-WithMessage "max-lines must be greater than zero"
        }

        Get-Content -LiteralPath $Target -Encoding UTF8 -TotalCount $MaxLines
    }

    "find-files" {
        if ($Args.Count -lt 2) {
            Stop-WithMessage "find-files requires <repo-relative-path> <file-glob>"
        }

        $Target = Get-RepoPath $Args[0]
        $Filter = $Args[1]

        Get-RepoFiles -Root $Target -Filter $Filter |
            Sort-Object FullName |
            ForEach-Object { ConvertTo-RepoRelative $_.FullName }
    }

    "grep" {
        if ($Args.Count -lt 2) {
            Stop-WithMessage "grep requires <repo-relative-path> <regex> [file-glob]"
        }

        $Target = Get-RepoPath $Args[0]
        $Pattern = $Args[1]
        $Filter = if ($Args.Count -ge 3) { $Args[2] } else { "*" }

        foreach ($File in (Get-RepoFiles -Root $Target -Filter $Filter | Sort-Object FullName)) {
            try {
                Select-String -LiteralPath $File.FullName -Pattern $Pattern -Encoding UTF8 |
                    ForEach-Object {
                        "{0}:{1}:{2}" -f (ConvertTo-RepoRelative $_.Path), $_.LineNumber, $_.Line.TrimEnd()
                    }
            } catch {
                Write-Warning "Skipped unreadable file: $(ConvertTo-RepoRelative $File.FullName)"
            }
        }
    }

    "changed-files" {
        & git -C $ProjectRootFull status --short
        if ($LASTEXITCODE -ne 0) {
            Stop-WithMessage "git status failed"
        }
    }
}
