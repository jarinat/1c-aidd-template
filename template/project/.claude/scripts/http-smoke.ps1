param(
    [Parameter(Position = 0)]
    [string] $Command = "run",

    [string] $ConfigFile,
    [string] $Profile,
    [string] $BaseUrl,
    [string] $EndpointPath,
    [string] $Url,
    [string] $Method = "POST",
    [string] $BodyFile,
    [string] $Body,
    [string] $ContentType = "application/json; charset=utf-8",
    [string] $ExpectedStatus,
    [string] $ExpectedSubstring,
    [int]    $TimeoutSec = 10,
    [string[]] $Header,
    [string] $RunLabel
)

$ErrorActionPreference = "Stop"

[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Show-Usage {
    Write-Output "Usage:"
    Write-Output "  http-smoke.cmd run -Profile <name> -EndpointPath <path> [-ConfigFile <path>]"
    Write-Output "                     [-Url <url> | -BaseUrl <url>] [-Method GET|POST|...]"
    Write-Output "                     [-BodyFile <path> | -Body <inline-json>]"
    Write-Output "                     [-ContentType <ct>] [-ExpectedStatus 200,400]"
    Write-Output "                     [-ExpectedSubstring <text>] [-TimeoutSec 10]"
    Write-Output "                     [-Header 'Name: Value' ...] [-RunLabel <label>]"
    Write-Output "  http-smoke.cmd help"
    Write-Output ""
    Write-Output "Config resolution: -ConfigFile > .claude/config/http-smoke.local.json > .claude/config/http-smoke.example.json."
    Write-Output "URL resolution: -Url > (-BaseUrl + -EndpointPath) > profile.baseUrl + -EndpointPath > `$env:HTTP_SMOKE_BASE_URL + -EndpointPath."
    Write-Output "Secrets stay in env vars referenced by profile.auth.usernameEnv/passwordEnv."
    Write-Output "Body templating: BodyFile or inline Body may contain {{TIMESTAMP}}."
    Write-Output "Exit codes: 0=PASS, 1=FAIL (status/substring), 3=NETWORK, 4=ENV, 5=USAGE."
}

function Write-StderrLine {
    param([string] $Text)
    [Console]::Error.WriteLine($Text)
}

function Emit-Result {
    param(
        [hashtable] $Payload,
        [int]       $ExitCode
    )

    $json = $Payload | ConvertTo-Json -Depth 8 -Compress
    Write-Output $json
    exit $ExitCode
}

function Stop-WithUsage {
    param([string] $Message, [int] $ExitCode = 5)
    Write-StderrLine $Message
    Show-Usage
    exit $ExitCode
}

function Resolve-RepoPath {
    param([string] $Path)
    if ([System.IO.Path]::IsPathRooted($Path)) { return $Path }
    return Join-Path -Path (Get-Location) -ChildPath $Path
}

function Test-Property {
    param([object] $Object, [string] $Name)
    if (-not $Object) { return $false }
    return $null -ne $Object.PSObject.Properties[$Name]
}

function Get-PropertyValue {
    param([object] $Object, [string] $Name)
    if (Test-Property -Object $Object -Name $Name) {
        return $Object.PSObject.Properties[$Name].Value
    }
    return $null
}

function Resolve-ConfigFile {
    if ($ConfigFile) {
        $resolved = Resolve-RepoPath -Path $ConfigFile
        if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) {
            Stop-WithUsage "Config file not found: $resolved" 4
        }
        return $resolved
    }

    $local = Resolve-RepoPath -Path ".claude/config/http-smoke.local.json"
    if (Test-Path -LiteralPath $local -PathType Leaf) { return $local }

    $example = Resolve-RepoPath -Path ".claude/config/http-smoke.example.json"
    if (Test-Path -LiteralPath $example -PathType Leaf) { return $example }

    return $null
}

function Load-Config {
    $path = Resolve-ConfigFile
    if (-not $path) { return $null }

    try {
        $text = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
        if (-not $text.Trim()) { return $null }
        return $text | ConvertFrom-Json
    } catch {
        Stop-WithUsage "Invalid HTTP-smoke config: $path. $($_.Exception.Message)" 4
    }
}

function Resolve-Profile {
    param([object] $Config)
    if (-not $Config) { return $null }

    $profileName = $Profile
    if (-not $profileName) {
        $profileName = Get-PropertyValue -Object $Config -Name "defaultProfile"
    }
    if (-not $profileName) { return $null }

    $profiles = Get-PropertyValue -Object $Config -Name "profiles"
    if (-not $profiles -or -not (Test-Property -Object $profiles -Name $profileName)) {
        Stop-WithUsage "HTTP-smoke profile not found: $profileName" 4
    }

    return @{
        name = $profileName
        data = Get-PropertyValue -Object $profiles -Name $profileName
    }
}

function Resolve-Url {
    param([object] $ProfileData)
    if ($Url) { return $Url }

    $resolvedBase = $BaseUrl
    if (-not $resolvedBase -and $ProfileData) {
        $resolvedBase = Get-PropertyValue -Object $ProfileData -Name "baseUrl"
    }
    if (-not $resolvedBase) {
        $resolvedBase = $env:HTTP_SMOKE_BASE_URL
    }

    if (-not $resolvedBase -or -not $EndpointPath) {
        Stop-WithUsage "URL not resolved. Provide -Url, -BaseUrl + -EndpointPath, profile.baseUrl + -EndpointPath, or `$env:HTTP_SMOKE_BASE_URL." 4
    }

    $base = $resolvedBase.TrimEnd('/')
    $path = $EndpointPath
    if (-not $path.StartsWith('/')) { $path = '/' + $path }
    return $base + $path
}

function Read-BodyText {
    if ($Body -and $BodyFile) {
        Stop-WithUsage "Provide either -Body or -BodyFile, not both." 5
    }

    if ($Body) { return $Body }
    if (-not $BodyFile) { return $null }

    $resolved = Resolve-RepoPath -Path $BodyFile
    if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) {
        Stop-WithUsage "Body file not found: $resolved" 4
    }

    return [System.IO.File]::ReadAllText($resolved, [System.Text.Encoding]::UTF8)
}

function Apply-Templating {
    param([string] $Text)
    if (-not $Text) { return $Text }
    $timestamp = (Get-Date).ToString("yyyyMMdd-HHmmss-fff")
    return $Text.Replace("{{TIMESTAMP}}", $timestamp)
}

function Add-HeadersFromObject {
    param([hashtable] $Map, [object] $HeadersObject)
    if (-not $HeadersObject) { return }
    foreach ($property in $HeadersObject.PSObject.Properties) {
        $Map[$property.Name] = [string] $property.Value
    }
}

function Add-HeadersFromList {
    param([hashtable] $Map, [string[]] $Items)
    if (-not $Items) { return }
    foreach ($item in $Items) {
        $idx = $item.IndexOf(':')
        if ($idx -lt 1) {
            Stop-WithUsage "Header must be 'Name: Value', got: $item" 5
        }
        $name  = $item.Substring(0, $idx).Trim()
        $value = $item.Substring($idx + 1).Trim()
        $Map[$name] = $value
    }
}

function Add-AuthHeader {
    param([hashtable] $Map, [object] $ProfileData)
    if (-not $ProfileData) { return }
    $auth = Get-PropertyValue -Object $ProfileData -Name "auth"
    if (-not $auth) { return }

    $type = Get-PropertyValue -Object $auth -Name "type"
    if (-not $type -or $type -eq "none") { return }

    if ($type -eq "basic") {
        $usernameEnv = Get-PropertyValue -Object $auth -Name "usernameEnv"
        $passwordEnv = Get-PropertyValue -Object $auth -Name "passwordEnv"
        if (-not $usernameEnv -or -not $passwordEnv) {
            Stop-WithUsage "Basic auth profile requires usernameEnv and passwordEnv." 4
        }
        $username = [Environment]::GetEnvironmentVariable($usernameEnv)
        $password = [Environment]::GetEnvironmentVariable($passwordEnv)
        if (-not $username -or -not $password) {
            Stop-WithUsage "Basic auth env vars are not set: $usernameEnv / $passwordEnv." 4
        }
        $token = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($username + ":" + $password))
        $Map["Authorization"] = "Basic $token"
        return
    }

    Stop-WithUsage "Unsupported auth.type: $type" 4
}

function Resolve-Headers {
    param([object] $ProfileData)
    $map = @{}
    if ($ProfileData) {
        Add-HeadersFromObject -Map $map -HeadersObject (Get-PropertyValue -Object $ProfileData -Name "defaultHeaders")
        Add-AuthHeader -Map $map -ProfileData $ProfileData
    }
    Add-HeadersFromList -Map $map -Items $Header
    return $map
}

function Parse-ExpectedStatus {
    if (-not $ExpectedStatus) { return @(200) }
    $parts = $ExpectedStatus -split ','
    $values = New-Object System.Collections.Generic.List[int]
    foreach ($part in $parts) {
        $trimmed = $part.Trim()
        if (-not $trimmed) { continue }
        $parsed = 0
        if (-not [int]::TryParse($trimmed, [ref] $parsed)) {
            Stop-WithUsage "ExpectedStatus must be a comma-separated list of integers, got: $ExpectedStatus" 5
        }
        $values.Add($parsed) | Out-Null
    }
    if ($values.Count -eq 0) { return @(200) }
    return $values.ToArray()
}

function Get-BodyExcerpt {
    param([string] $Text, [int] $MaxLen = 2000)
    if (-not $Text) { return "" }
    if ($Text.Length -le $MaxLen) { return $Text }
    return $Text.Substring(0, $MaxLen) + "...<truncated>"
}

function Invoke-Smoke {
    $config = Load-Config
    $profileInfo = Resolve-Profile -Config $config
    $profileData = $null
    $profileName = $null
    if ($profileInfo) {
        $profileData = $profileInfo.data
        $profileName = $profileInfo.name
    }

    $resolvedUrl = Resolve-Url -ProfileData $profileData
    $rawBody     = Read-BodyText
    $bodyText    = Apply-Templating -Text $rawBody
    $headers     = Resolve-Headers -ProfileData $profileData
    $expectedStatusList = Parse-ExpectedStatus

    $startedAt = Get-Date
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    $httpStatus          = $null
    $responseBody        = ""
    $networkError        = $null
    $contentLengthHeader = $null
    $contentTypeHeader   = $null

    try {
        $request = [System.Net.HttpWebRequest]::Create($resolvedUrl)
        $request.Method      = $Method
        $request.Timeout     = $TimeoutSec * 1000
        $request.ReadWriteTimeout = $TimeoutSec * 1000
        $request.AllowAutoRedirect = $false
        $request.KeepAlive   = $false

        foreach ($name in $headers.Keys) {
            $value = $headers[$name]
            switch -Regex ($name) {
                '^(?i)Content-Type$'   { $request.ContentType = $value; continue }
                '^(?i)Accept$'         { $request.Accept = $value; continue }
                '^(?i)User-Agent$'     { $request.UserAgent = $value; continue }
                '^(?i)Authorization$'  { $request.Headers['Authorization'] = $value; continue }
                default                { $request.Headers[$name] = $value }
            }
        }

        if ($null -ne $bodyText) {
            $request.ContentType = $ContentType
            $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($bodyText)
            $request.ContentLength = $bodyBytes.Length
            $requestStream = $request.GetRequestStream()
            $requestStream.Write($bodyBytes, 0, $bodyBytes.Length)
            $requestStream.Close()
        }

        $response = $null
        try {
            $response = $request.GetResponse()
        } catch [System.Net.WebException] {
            $response = $_.Exception.Response
            if (-not $response) {
                $networkError = $_.Exception.Message
            }
        }

        if ($response) {
            try { $httpStatus = [int] $response.StatusCode } catch { $httpStatus = $null }

            try {
                $contentLengthHeader = $response.Headers['Content-Length']
                $contentTypeHeader   = $response.Headers['Content-Type']
            } catch {}

            try {
                $stream = $response.GetResponseStream()
                if ($stream) {
                    $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8)
                    $responseBody = $reader.ReadToEnd()
                    $reader.Dispose()
                }
            } catch {
                $responseBody = ""
            }

            try { $response.Close() } catch {}
        }
    }
    catch {
        $networkError = $_.Exception.Message
    }
    finally {
        $stopwatch.Stop()
    }

    if ($networkError) {
        $payload = @{
            result      = "FAIL"
            failReasons = @("network: $networkError")
            url         = $resolvedUrl
            method      = $Method
            profile     = $profileName
            elapsedMs   = $stopwatch.ElapsedMilliseconds
            startedAt   = $startedAt.ToString("yyyy-MM-ddTHH:mm:ss.fffK")
            runLabel    = $RunLabel
            expected    = @{ status = $expectedStatusList; substring = $ExpectedSubstring }
        }
        Emit-Result -Payload $payload -ExitCode 3
    }

    $failReasons = New-Object System.Collections.Generic.List[string]
    $statusOk = $expectedStatusList -contains $httpStatus
    if (-not $statusOk) {
        $failReasons.Add("status: expected $($expectedStatusList -join ','), got $httpStatus") | Out-Null
    }

    $substringOk = $true
    if ($ExpectedSubstring) {
        $substringOk = $responseBody -and ($responseBody.IndexOf($ExpectedSubstring) -ge 0)
        if (-not $substringOk) {
            $failReasons.Add("substring not found: $ExpectedSubstring") | Out-Null
        }
    }

    $result   = if ($failReasons.Count -eq 0) { "PASS" } else { "FAIL" }
    $exitCode = if ($failReasons.Count -eq 0) { 0 } else { 1 }

    $bodyLength = 0
    if ($responseBody) { $bodyLength = $responseBody.Length }

    $payload = @{
        result      = $result
        failReasons = $failReasons.ToArray()
        url         = $resolvedUrl
        method      = $Method
        profile     = $profileName
        httpStatus  = $httpStatus
        elapsedMs   = $stopwatch.ElapsedMilliseconds
        startedAt   = $startedAt.ToString("yyyy-MM-ddTHH:mm:ss.fffK")
        runLabel    = $RunLabel
        expected    = @{ status = $expectedStatusList; substring = $ExpectedSubstring }
        actual      = @{
            bodyExcerpt   = Get-BodyExcerpt -Text $responseBody
            bodyLength    = $bodyLength
            contentType   = $contentTypeHeader
            contentLength = $contentLengthHeader
        }
    }
    Emit-Result -Payload $payload -ExitCode $exitCode
}

switch -Regex ($Command) {
    "^help$"  { Show-Usage; exit 0 }
    "^run$"   { Invoke-Smoke }
    default   { Stop-WithUsage "Unknown command: $Command" 5 }
}

