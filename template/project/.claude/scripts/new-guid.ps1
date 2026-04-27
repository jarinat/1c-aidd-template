param(
    [Parameter(Position = 0)]
    [string] $Command,

    [string] $Count = "1"
)

$ErrorActionPreference = "Stop"

function Show-Usage {
    Write-Output "Usage:"
    Write-Output "  new-guid.cmd"
    Write-Output "  new-guid.cmd -Count <number>"
    Write-Output "  new-guid.cmd help"
}

function Stop-WithUsage {
    param(
        [string] $Message
    )

    [Console]::Error.WriteLine($Message)
    Show-Usage
    exit 2
}

if ($Command) {
    if ($Command -ieq "help") {
        Show-Usage
        exit 0
    }

    Stop-WithUsage "Unknown command: $Command"
}

[int] $ParsedCount = 0

if (-not [int]::TryParse($Count, [ref] $ParsedCount)) {
    Stop-WithUsage "-Count must be an integer between 1 and 100."
}

if ($ParsedCount -lt 1 -or $ParsedCount -gt 100) {
    Stop-WithUsage "-Count must be between 1 and 100."
}

for ($Index = 0; $Index -lt $ParsedCount; $Index++) {
    [guid]::NewGuid().ToString("D")
}
