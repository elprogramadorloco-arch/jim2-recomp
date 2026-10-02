# Refuse to package anything that is not publishable source: no disc images,
# no generated (game-derived) C, no binaries, no build output, no private paths.
[CmdletBinding()]
param([string]$Root = (Split-Path -Parent $PSScriptRoot))

$ErrorActionPreference = 'Stop'
$Root = [IO.Path]::GetFullPath($Root)
$bad = New-Object System.Collections.Generic.List[string]

$forbiddenDirs = @('out', 'update', 'tools\.build', 'project\generated', 'project\build-release',
                   'project\build-recompiler', 'project\psxrecomp', 'project\recomp-ui')
foreach ($d in $forbiddenDirs) {
    if (Test-Path -LiteralPath (Join-Path $Root $d)) { $bad.Add("forbidden directory: $d") }
}
$forbiddenExt = '\.(bin|cue|iso|img|chd|ccd|sub|mcd|mcr|exe|dll|lib|a|o|obj|pdb|zip|7z|so|dylib)$'
Get-ChildItem -LiteralPath $Root -Recurse -File -Force | ForEach-Object {
    $rel = $_.FullName.Substring($Root.Length).TrimStart('\')
    if ($rel -match $forbiddenExt) { $bad.Add("forbidden file type: $rel") }
    if ($rel -like 'data\*' -and $rel -ne 'data\README.txt') { $bad.Add("user data: $rel") }
    if ($rel -match '(_full_\d+\.c|_dispatch\.c|overlays_static.*\.c)$') { $bad.Add("generated game C: $rel") }
    if ($_.Length -gt 5MB) { $bad.Add("unexpectedly large file: $rel") }
    if ($_.Extension -in '.ps1', '.bat', '.md', '.txt', '.json', '.toml', '.c', '.h') {
        $text = Get-Content -LiteralPath $_.FullName -Raw
        if ($text -match '(?i)[a-z]:[\\/](proyectos|users)[\\/]') { $bad.Add("private absolute path in $rel") }
        if ($text -match '(ghp_|github_pat_)[A-Za-z0-9_]{20,}') { $bad.Add("token-like string in $rel") }
    }
}
if ($bad.Count) {
    $bad | ForEach-Object { Write-Host "  x $_" -ForegroundColor Red }
    throw "Public tree check failed ($($bad.Count) problems): $Root"
}
Write-Host "Public tree OK: $Root" -ForegroundColor Green
