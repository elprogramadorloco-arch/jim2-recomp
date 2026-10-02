# Shared pins and helpers for run.bat / update.bat (Windows PowerShell 5.1+).
# Everything this project downloads is pinned to an exact version and SHA-256.
$ErrorActionPreference = 'Stop'

$Script:PublicRoot = Split-Path -Parent $PSScriptRoot
$Script:BuildRoot  = Join-Path $PublicRoot 'tools\.build'
$Script:Downloads  = Join-Path $BuildRoot 'downloads'
$Script:DataDir    = Join-Path $PublicRoot 'data'
$Script:OutDir     = Join-Path $PublicRoot 'out'
$Script:ExeName    = 'EarthwormJim2_Recompiled.exe'

# Portable toolchain: LLVM-MinGW clang, CMake, Ninja, Python 3.12, SDL3, zlib.
# No Visual Studio / Build Tools / system CMake or Python is needed.
$Script:Toolchain = [pscustomobject]@{
    Name   = 'cmake-clang-v1-windows-x64.zip'
    Url    = 'https://github.com/RetroPortingToolKit/RetroPorting-Toolchains/releases/download/v1.0.14/cmake-clang-v1-windows-x64.zip'
    Sha256 = '28DA9742385E7FF875B3D9311E8ED89DBDC84F27B6ECBA2BC0D0ACC11F6D2B4D'
    Size   = 209497009
}

# Framework sources, fetched from their upstream repositories at fixed commits
# (they are not redistributed by this project; see THIRD_PARTY_NOTICES.md).
$Script:Framework = @(
    [pscustomobject]@{ Repo = 'mstan/psxrecomp'; Commit = 'f60aae21590a895a35ac8ca5136ae1e2431cd571'
        Sha256 = 'ABF494248388422E834E180C0903123B9ECCE1DE852F6573ED1F3E0B97D1C168'; Dest = 'psxrecomp' }
    [pscustomobject]@{ Repo = 'RetroPortingToolKit/recomp-ui'; Commit = '5de138a8b176ee66ee583ce1748f2059b97e15ca'
        Sha256 = '9C88D64265273A78B9AAD673A35D63A57116FA78E8427DC4FBEE3FB6A9F0DEDF'; Dest = 'recomp-ui' }
    [pscustomobject]@{ Repo = 'RetroPortingToolKit/recomp-net'; Commit = 'c58f125a3cc3468fc84012cf4eeb50cc0b62c379'
        Sha256 = '0FEEFC40DCEE7DEF24C66CC4AF76C12C425F66CC01AECE7B79D955E97A6BC03E'; Dest = 'psxrecomp\lib\recomp-net' }
    [pscustomobject]@{ Repo = 'RetroPortingToolKit/rbengine'; Commit = '2a03e73693acee0fb78076ea058642c931bef12e'
        Sha256 = '3879EEE1AB04BD3D36D164779ACEA68D0FD6EEFC904C4A8D393AE41464B80E82'; Dest = 'psxrecomp\lib\retcomm-rbengine' }
)

# The supported disc: Earthworm Jim 2 (Europe), SLES-00343, Redump, 15 tracks.
$Script:Disc = [pscustomobject]@{
    Serial      = 'SLES-00343'
    Tracks      = 15
    DataSize    = 33631248
    DataSha256  = 'D251CF65BB60EE375778F4369CF74FB88371E07EAB51EC337C0AD34F8DEF932B'
}

function Write-Step([int]$Index, [int]$Total, [string]$Text) {
    $pct = [int](100 * ($Index - 1) / $Total)
    Write-Progress -Activity 'Earthworm Jim 2 Recompiled' -Status "[$Index/$Total] $Text" -PercentComplete $pct
    Write-Host ''
    Write-Host ("== [{0}/{1}] {2}" -f $Index, $Total, $Text) -ForegroundColor Cyan
}

function Write-Ok([string]$Text)   { Write-Host "   OK  $Text" -ForegroundColor Green }
function Write-Info([string]$Text) { Write-Host "   ..  $Text" }

function Get-Sha256([string]$Path) {
    (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToUpperInvariant()
}

function Invoke-VerifiedDownload([string]$Uri, [string]$Destination, [string]$ExpectedSha256) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Destination) | Out-Null
    if ((Test-Path -LiteralPath $Destination) -and (Get-Sha256 $Destination) -eq $ExpectedSha256) {
        Write-Ok "cached $(Split-Path -Leaf $Destination)"
        return
    }
    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    $last = $null
    foreach ($attempt in 1..5) {
        Remove-Item -LiteralPath $Destination -Force -ErrorAction SilentlyContinue
        Write-Info "downloading $(Split-Path -Leaf $Destination) (attempt $attempt/5)"
        try {
            if ($curl) {
                & $curl.Source --location --fail --show-error --silent --connect-timeout 30 `
                    --max-time 1800 --retry 3 --output $Destination $Uri
                if ($LASTEXITCODE -ne 0) { throw "curl.exe exited with code $LASTEXITCODE" }
            } else {
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                Invoke-WebRequest -UseBasicParsing -Uri $Uri -OutFile $Destination -TimeoutSec 1800
            }
            $got = Get-Sha256 $Destination
            if ($got -ne $ExpectedSha256) { throw "SHA-256 mismatch (got $got, expected $ExpectedSha256)" }
            Write-Ok "verified $(Split-Path -Leaf $Destination)"
            return
        } catch {
            $last = $_.Exception.Message
            Start-Sleep -Seconds ([Math]::Min(30, 3 * $attempt))
        }
    }
    throw "Download failed: $Uri`n$last"
}

function Expand-Zip([string]$Zip, [string]$Destination) {
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    $tar = Join-Path $env:SystemRoot 'System32\tar.exe'
    if (Test-Path -LiteralPath $tar) {
        & $tar -xf $Zip -C $Destination
        if ($LASTEXITCODE -ne 0) { throw "tar.exe could not extract $Zip" }
    } else {
        Expand-Archive -LiteralPath $Zip -DestinationPath $Destination -Force
    }
}

function Assert-UnderBuildRoot([string]$Path) {
    $root = [IO.Path]::GetFullPath($BuildRoot).TrimEnd('\') + '\'
    $full = [IO.Path]::GetFullPath($Path)
    if (-not $full.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to modify a path outside tools\.build: $full"
    }
}

function Remove-BuildPath([string]$Path) {
    Assert-UnderBuildRoot $Path
    if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Recurse -Force }
}

function Get-PublicVersion {
    (Get-Content -LiteralPath (Join-Path $PublicRoot 'version.txt') -Raw).Trim()
}

function Read-State {
    $p = Join-Path $BuildRoot 'state.json'
    if (Test-Path -LiteralPath $p) { return Get-Content -LiteralPath $p -Raw | ConvertFrom-Json }
    return [pscustomobject]@{}
}

function Save-State($State) {
    New-Item -ItemType Directory -Force -Path $BuildRoot | Out-Null
    $State | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $BuildRoot 'state.json') -Encoding UTF8
}

function Set-StateValue($State, [string]$Name, $Value) {
    if ($State.PSObject.Properties[$Name]) { $State.$Name = $Value }
    else { $State | Add-Member -NotePropertyName $Name -NotePropertyValue $Value }
}

function Get-StateValue($State, [string]$Name) {
    if ($State.PSObject.Properties[$Name]) { return $State.$Name }
    return $null
}

function Invoke-Native([string]$Exe, [string[]]$Arguments, [string]$Log) {
    # Run a tool, stream nothing to the console (logs can be huge), keep a log.
    $argLine = ($Arguments | ForEach-Object { Quote-Arg $_ }) -join ' '
    $p = Start-Process -FilePath $Exe -ArgumentList $argLine -NoNewWindow -Wait -PassThru `
        -RedirectStandardOutput $Log -RedirectStandardError "$Log.err"
    if ($p.ExitCode -ne 0) {
        Write-Host ''
        Get-Content -LiteralPath $Log -Tail 25 -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "   | $_" }
        Get-Content -LiteralPath "$Log.err" -Tail 25 -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "   | $_" }
        throw "$(Split-Path -Leaf $Exe) failed (exit $($p.ExitCode)). Full log: $Log"
    }
}

function Quote-Arg([string]$s) {
    if ($s -match '[\s"]') { return '"' + ($s -replace '"', '\"') + '"' }
    return $s
}
