[CmdletBinding()]
param(
    [Parameter(Position = 0, Mandatory = $true)]
    [ValidatePattern("^[A-Za-z0-9][A-Za-z0-9._-]*$")]
    [string]$Ticket
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
$AiddDocs = Join-Path $ProjectRootFull "aidd\docs"

function Stop-WithMessage {
    param([Parameter(Mandatory = $true)][string]$Message)

    Write-Error $Message
    exit 2
}

function ConvertTo-RepoRelative {
    param([Parameter(Mandatory = $true)][string]$Path)

    $FullPath = [System.IO.Path]::GetFullPath($Path)
    if ($FullPath.Equals($ProjectRootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
        return "."
    }

    return $FullPath.Substring($ProjectRootFull.Length).TrimStart('\', '/') -replace "\\", "/"
}

function Assert-InRepo {
    param([Parameter(Mandatory = $true)][string]$Path)

    $FullPath = [System.IO.Path]::GetFullPath($Path)
    $Comparison = [System.StringComparison]::OrdinalIgnoreCase
    $InsideRoot = $FullPath.Equals($ProjectRootFull, $Comparison) -or
        $FullPath.StartsWith($ProjectRootFull + [System.IO.Path]::DirectorySeparatorChar, $Comparison) -or
        $FullPath.StartsWith($ProjectRootFull + [System.IO.Path]::AltDirectorySeparatorChar, $Comparison)

    if (-not $InsideRoot) {
        Stop-WithMessage "Path leaves repository root: $Path"
    }

    return $FullPath
}

New-Item -ItemType Directory -Path (Assert-InRepo $AiddDocs) -Force | Out-Null

$ActiveTicketPath = Assert-InRepo (Join-Path $AiddDocs ".active_ticket")
Set-Content -LiteralPath $ActiveTicketPath -Value $Ticket -Encoding UTF8
Write-Output ("UPDATED {0}" -f (ConvertTo-RepoRelative $ActiveTicketPath))

$ArtifactDirs = @(
    "prd",
    "plan",
    "tasklist",
    "research",
    "feedback",
    "review"
)

foreach ($Dir in $ArtifactDirs) {
    $DirPath = Assert-InRepo (Join-Path $AiddDocs $Dir)
    if (Test-Path -LiteralPath $DirPath -PathType Container) {
        Write-Output ("EXISTS  {0}" -f (ConvertTo-RepoRelative $DirPath))
    } else {
        New-Item -ItemType Directory -Path $DirPath -Force | Out-Null
        Write-Output ("CREATED {0}" -f (ConvertTo-RepoRelative $DirPath))
    }
}

$FeedbackPath = Assert-InRepo (Join-Path $AiddDocs ("feedback\{0}.md" -f $Ticket))
if (Test-Path -LiteralPath $FeedbackPath -PathType Leaf) {
    Write-Output ("EXISTS  {0}" -f (ConvertTo-RepoRelative $FeedbackPath))
} else {
    New-Item -ItemType File -Path $FeedbackPath -Force | Out-Null
    Write-Output ("CREATED {0}" -f (ConvertTo-RepoRelative $FeedbackPath))
}
