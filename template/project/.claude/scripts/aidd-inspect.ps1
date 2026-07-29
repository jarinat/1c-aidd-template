[CmdletBinding()]
param(
    [Parameter(Position = 0, Mandatory = $true)]
    [ValidateSet("help", "list", "read", "find-files", "grep", "changed-files", "review-diff")]
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
  aidd-inspect.ps1 review-diff summary [<git-diff-refspec>]
  aidd-inspect.ps1 review-diff file <repo-relative-file> [<git-diff-refspec>]
  aidd-inspect.ps1 review-diff bsl [<git-diff-refspec>]
  aidd-inspect.ps1 review-diff metadata [<git-diff-refspec>]

Examples:
  .claude/scripts/aidd-inspect.cmd list src
  .claude/scripts/aidd-inspect.cmd find-files src *.rights
  .claude/scripts/aidd-inspect.cmd grep src "OldName|NewName" *.bsl
  .claude/scripts/aidd-inspect.cmd review-diff summary
  .claude/scripts/aidd-inspect.cmd review-diff metadata HEAD~1..HEAD
"@
}

function Invoke-Git {
    param([Parameter(Mandatory = $true)][string[]]$GitArgs)

    # Git C-quotes non-ASCII paths by default. Keep paths literal so the
    # extension filters below and the subsequent `git diff -- <path>` calls
    # receive the same repo-relative name.
    $Output = & git -c core.quotePath=false -C $ProjectRootFull @GitArgs
    if ($LASTEXITCODE -ne 0) {
        Stop-WithMessage "git $($GitArgs -join ' ') failed"
    }

    return @($Output)
}

function Get-GitDiffOutput {
    param(
        [string[]]$DiffArgs,
        [string]$Path
    )

    $Result = @()
    if ($DiffArgs.Count -gt 0) {
        $ArgsList = @("diff") + $DiffArgs
        if (-not [string]::IsNullOrWhiteSpace($Path)) {
            $ArgsList += @("--", $Path)
        }
        return Invoke-Git $ArgsList
    }

    $UnstagedArgs = @("diff", "--")
    $StagedArgs = @("diff", "--cached", "--")
    if (-not [string]::IsNullOrWhiteSpace($Path)) {
        $UnstagedArgs += $Path
        $StagedArgs += $Path
    }

    $Unstaged = Invoke-Git $UnstagedArgs
    $Staged = Invoke-Git $StagedArgs

    if ($Staged.Count -gt 0) {
        $Result += "## staged diff"
        $Result += $Staged
    }
    if ($Unstaged.Count -gt 0) {
        $Result += "## unstaged diff"
        $Result += $Unstaged
    }

    return $Result
}

function Get-ReviewDiffArgs {
    param([string[]]$RawArgs)

    if ($RawArgs.Count -eq 0) {
        return @()
    }

    return @($RawArgs[0])
}

function Get-ChangedFilesFromDiffNameStatus {
    param([string[]]$DiffArgs)

    $Output = if ($DiffArgs.Count -gt 0) {
        Invoke-Git (@("diff", "--name-status", "--find-renames") + $DiffArgs)
    } else {
        (Invoke-Git @("diff", "--cached", "--name-status", "--find-renames")) +
            (Invoke-Git @("diff", "--name-status", "--find-renames"))
    }

    $Files = @()
    foreach ($Line in $Output) {
        if ([string]::IsNullOrWhiteSpace($Line)) {
            continue
        }
        $Parts = $Line -split "`t"
        if ($Parts.Count -ge 3 -and $Parts[0] -match "^R") {
            $Files += $Parts[2]
        } elseif ($Parts.Count -ge 2) {
            $Files += $Parts[1]
        }
    }

    return @($Files | Sort-Object -Unique)
}

function Show-ReviewDiffSummary {
    param([string[]]$DiffArgs)

    "## name-status"
    if ($DiffArgs.Count -gt 0) {
        Invoke-Git (@("diff", "--name-status", "--find-renames") + $DiffArgs)
        ""
        "## stat"
        Invoke-Git (@("diff", "--stat") + $DiffArgs)
        return
    }

    "### staged"
    Invoke-Git @("diff", "--cached", "--name-status", "--find-renames")
    "### unstaged"
    Invoke-Git @("diff", "--name-status", "--find-renames")
    ""
    "## stat"
    "### staged"
    Invoke-Git @("diff", "--cached", "--stat")
    "### unstaged"
    Invoke-Git @("diff", "--stat")
}

function Show-ReviewDiffFile {
    param(
        [Parameter(Mandatory = $true)][string]$RepoPath,
        [string[]]$DiffArgs
    )

    $ResolvedPath = Get-RepoPath $RepoPath $false
    $Relative = ConvertTo-RepoRelative $ResolvedPath
    Get-GitDiffOutput -DiffArgs $DiffArgs -Path $Relative
}

function Show-ReviewDiffBsl {
    param([string[]]$DiffArgs)

    $Files = Get-ChangedFilesFromDiffNameStatus $DiffArgs |
        Where-Object { $_ -match "\.bsl$" }

    if ($Files.Count -eq 0) {
        "No changed .bsl files."
        return
    }

    foreach ($File in $Files) {
        "## $File"
        $Diff = Get-GitDiffOutput -DiffArgs $DiffArgs -Path $File
        $Interesting = $Diff | Where-Object {
            $_ -match "^(diff --git|@@|[+-]\s*(Процедура|Функция|КонецПроцедуры|КонецФункции)\b|[+-].*(ОбщегоНазначения\.ЗначениеРеквизитаОбъекта|Выполнить\(|Запрос\.Текст|Записать\(|УстановитьПривилегированныйРежим|Новый\s+Запрос))"
        }
        if ($Interesting.Count -gt 0) {
            $Interesting
        } else {
            "Changed, but no procedure/function signature or high-risk BSL pattern matched. Use `review-diff file $File` for the full diff."
        }
        ""
    }
}

function Show-ReviewDiffMetadata {
    param([string[]]$DiffArgs)

    $Files = Get-ChangedFilesFromDiffNameStatus $DiffArgs |
        Where-Object { $_ -match "\.(mdo|dcs|form|rights|xml)$" }

    if ($Files.Count -eq 0) {
        "No changed metadata/XML files."
        return
    }

    $SensitivePattern = "(<(/)?(totalField|field|calculatedField|dataSet|query|template|rights|right|object|childObject)|<(/)?dcsset:(row|column|selection|filter|order|settings|item|groupItem|outputParameters|conditionalAppearance|userSettings|parameter)|<(/)?dcscor:(item|parameter)|<(/)?form:|<(/)?mdclass:|<(/)?xr:|Enum\.|Configuration\.)"

    foreach ($File in $Files) {
        "## $File"
        $Diff = Get-GitDiffOutput -DiffArgs $DiffArgs -Path $File
        $Interesting = $Diff | Where-Object {
            $_ -match "^(diff --git|@@)" -or
                ($_ -match "^[+-]" -and $_ -match $SensitivePattern)
        }
        if ($Interesting.Count -gt 0) {
            $Interesting
        } else {
            "Changed, but no known sensitive metadata/XML section matched. Use `review-diff file $File` for the full diff."
        }
        ""
    }
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

    "review-diff" {
        if ($Args.Count -lt 1) {
            Stop-WithMessage "review-diff requires summary|file|bsl|metadata"
        }

        $Subcommand = $Args[0]
        switch ($Subcommand) {
            "summary" {
                $DiffArgs = Get-ReviewDiffArgs @($Args | Select-Object -Skip 1)
                Show-ReviewDiffSummary $DiffArgs
            }
            "file" {
                if ($Args.Count -lt 2) {
                    Stop-WithMessage "review-diff file requires <repo-relative-file> [<git-diff-refspec>]"
                }
                $DiffArgs = Get-ReviewDiffArgs @($Args | Select-Object -Skip 2)
                Show-ReviewDiffFile -RepoPath $Args[1] -DiffArgs $DiffArgs
            }
            "bsl" {
                $DiffArgs = Get-ReviewDiffArgs @($Args | Select-Object -Skip 1)
                Show-ReviewDiffBsl $DiffArgs
            }
            "metadata" {
                $DiffArgs = Get-ReviewDiffArgs @($Args | Select-Object -Skip 1)
                Show-ReviewDiffMetadata $DiffArgs
            }
            default {
                Stop-WithMessage "Unknown review-diff subcommand: $Subcommand"
            }
        }
    }
}
