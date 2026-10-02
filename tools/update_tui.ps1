# Update to the latest GitHub Release: download the source-only package named in
# update-manifest.json, verify its SHA-256, replace only public source files
# (data\, out\ and tools\.build\ are never touched) and rebuild what changed.
[CmdletBinding()]
param([switch]$NoPause, [switch]$CheckOnly)

. (Join-Path $PSScriptRoot 'common.ps1')
$Host.UI.RawUI.WindowTitle = 'Earthworm Jim 2 Recompiled - update'
function Pause-IfNeeded { if (-not $NoPause) { Write-Host ''; Read-Host 'Press Enter to close' | Out-Null } }

$UpdateDir = Join-Path $PublicRoot 'update'
$Keep = @('data', 'out', 'update', 'tools\.build')

function Get-Json([string]$Uri) {
    $tmp = Join-Path $env:TEMP ("ewj2-manifest-{0}.json" -f [guid]::NewGuid())
    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    if ($curl) {
        & $curl.Source --location --fail --silent --show-error --connect-timeout 30 --retry 3 --output $tmp $Uri
        if ($LASTEXITCODE -ne 0) { throw "Could not download $Uri" }
    } else {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -UseBasicParsing -Uri $Uri -OutFile $tmp
    }
    try { return [IO.File]::ReadAllText($tmp, [Text.Encoding]::UTF8) | ConvertFrom-Json } finally { Remove-Item $tmp -ErrorAction SilentlyContinue }
}

function Get-RelativeFiles([string]$Root) {
    Get-ChildItem -LiteralPath $Root -Recurse -File -Force | ForEach-Object {
        $_.FullName.Substring($Root.Length).TrimStart('\')
    } | Where-Object {
        $rel = $_
        -not ($Keep | Where-Object { $rel -eq $_ -or $rel.StartsWith("$_\", [StringComparison]::OrdinalIgnoreCase) })
    }
}

try {
    $config = Get-Content -LiteralPath (Join-Path $PublicRoot 'update-config.json') -Raw | ConvertFrom-Json
    $current = Get-PublicVersion
    Write-Host "Installed version: $current"
    $manifest = Get-Json $config.manifestUrl
    Write-Host "Latest version:    $($manifest.version)"
    if ([version]$manifest.version -le [version]$current) {
        Write-Host 'You already have the latest version.' -ForegroundColor Green
        Pause-IfNeeded; exit 0
    }
    Write-Host ''
    Write-Host "What's new:" -ForegroundColor Cyan
    Write-Host $manifest.notes
    if ($CheckOnly) { Pause-IfNeeded; exit 0 }
    if (-not $NoPause) {
        $a = Read-Host "`nUpdate to $($manifest.version) now? [Y/n]"
        if ($a -ne '' -and $a -notmatch '^[YySs]') { exit 0 }
    }

    if (Test-Path -LiteralPath $UpdateDir) { Remove-Item -LiteralPath $UpdateDir -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $UpdateDir | Out-Null
    $zip = Join-Path $UpdateDir 'package.zip'
    Invoke-VerifiedDownload $manifest.packageUrl $zip ($manifest.packageSha256.ToUpperInvariant())
    $pkg = Join-Path $UpdateDir 'package'
    Expand-Zip $zip $pkg
    $pkgVersion = (Get-Content -LiteralPath (Join-Path $pkg 'version.txt') -Raw).Trim()
    if ($pkgVersion -ne $manifest.version) { throw "Package version $pkgVersion does not match manifest $($manifest.version)." }

    # Back up every public file we may replace, then overlay the package.
    $backup = Join-Path $UpdateDir 'backup'
    foreach ($rel in Get-RelativeFiles $PublicRoot) {
        $dst = Join-Path $backup $rel
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dst) | Out-Null
        Copy-Item -LiteralPath (Join-Path $PublicRoot $rel) -Destination $dst -Force
    }
    try {
        foreach ($rel in Get-RelativeFiles $pkg) {
            $dst = Join-Path $PublicRoot $rel
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dst) | Out-Null
            Copy-Item -LiteralPath (Join-Path $pkg $rel) -Destination $dst -Force
        }
        Write-Host "Sources updated to $pkgVersion. Rebuilding what changed..." -ForegroundColor Cyan
        & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PublicRoot 'tools\run_tui.ps1') -NoPause -NoLaunch
        if ($LASTEXITCODE -ne 0) { throw 'The rebuild failed.' }
    } catch {
        Write-Host 'Update failed; restoring the previous version...' -ForegroundColor Yellow
        foreach ($rel in Get-RelativeFiles $backup) {
            Copy-Item -LiteralPath (Join-Path $backup $rel) -Destination (Join-Path $PublicRoot $rel) -Force
        }
        throw
    }
    Remove-Item -LiteralPath $UpdateDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "Updated to $pkgVersion." -ForegroundColor Green
} catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Pause-IfNeeded; exit 1
}
Pause-IfNeeded
exit 0
