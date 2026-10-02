[CmdletBinding()]
param([switch]$NoPause, [switch]$ValidateOnly, [switch]$Force, [switch]$NoLaunch)

. (Join-Path $PSScriptRoot 'common.ps1')
$Host.UI.RawUI.WindowTitle = 'Earthworm Jim 2 Recompiled - setup'

function Pause-IfNeeded { if (-not $NoPause) { Write-Host ''; Read-Host 'Press Enter to close' | Out-Null } }

Write-Host '==============================================================' -ForegroundColor Yellow
Write-Host '  Earthworm Jim 2 Recompiled  -  v'(Get-PublicVersion) -ForegroundColor Yellow
Write-Host '  Static recompilation of the PlayStation game (SLES-00343)' -ForegroundColor Yellow
Write-Host '==============================================================' -ForegroundColor Yellow
Write-Host 'Your disc stays on this PC. Everything generated from it goes to'
Write-Host 'out\ and tools\.build\ and must not be shared.'

$exe = Join-Path $OutDir $ExeName
try {
    & (Join-Path $PSScriptRoot 'build.ps1') -ValidateOnly:$ValidateOnly -Force:$Force
} catch {
    Write-Progress -Activity 'Earthworm Jim 2 Recompiled' -Completed
    Write-Host ''
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host 'Logs: tools\.build\logs'
    Pause-IfNeeded
    exit 1
}
if ($ValidateOnly) { Pause-IfNeeded; exit 0 }

Write-Host ''
Write-Host "Done. Play with: out\$ExeName" -ForegroundColor Green
if (-not $NoLaunch -and -not $NoPause) {
    $answer = Read-Host 'Launch the game now? [Y/n]'
    if ($answer -eq '' -or $answer -match '^[YySs]') {
        Start-Process -FilePath $exe -WorkingDirectory $OutDir
    }
}
exit 0
