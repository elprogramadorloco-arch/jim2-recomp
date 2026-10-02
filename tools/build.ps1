# Private local build of Earthworm Jim 2 Recompiled from the user's own disc.
#   1 validate disc   2 toolchain   3 framework   4 project   5 emitters
#   6 generate C      7 runtime     8 install into out\
# Steps whose inputs did not change are skipped (tools\.build\state.json).
[CmdletBinding()]
param([switch]$ValidateOnly, [switch]$Force)

. (Join-Path $PSScriptRoot 'common.ps1')

$Total = 8
$State = Read-State
$Version = Get-PublicVersion
$Work = Join-Path $BuildRoot 'work'
$Tc = Join-Path $BuildRoot 'toolchain'
$Proj = Join-Path $Work 'EarthwormJim2Recomp'
$Logs = Join-Path $BuildRoot 'logs'
New-Item -ItemType Directory -Force -Path $BuildRoot, $Downloads, $Logs | Out-Null

# ---------------------------------------------------------------- 1 disc --
Write-Step 1 $Total 'Validating your Earthworm Jim 2 (Europe) disc in data\'
$cues = @(Get-ChildItem -LiteralPath $DataDir -Filter *.cue -File -ErrorAction SilentlyContinue)
if ($cues.Count -ne 1) {
    throw ("Put exactly one .cue file and its .bin tracks in data\ (found {0} .cue files). " +
           "See data\README.txt.") -f $cues.Count
}
$Cue = $cues[0].FullName
$files = @(); $tracks = 0
foreach ($line in Get-Content -LiteralPath $Cue) {
    if ($line -match '^\s*FILE\s+"(.+)"\s+BINARY') { $files += $Matches[1] }
    if ($line -match '^\s*TRACK\s+\d+') { $tracks++ }
}
foreach ($f in $files) {
    if (-not (Test-Path -LiteralPath (Join-Path $DataDir $f) -PathType Leaf)) {
        throw "The cue references '$f', which is not in data\."
    }
}
if ($tracks -ne $Disc.Tracks) {
    throw "Expected the full Redump dump with $($Disc.Tracks) tracks; the cue has $tracks."
}
$track1 = Join-Path $DataDir $files[0]
if ((Get-Item -LiteralPath $track1).Length -ne $Disc.DataSize -or (Get-Sha256 $track1) -ne $Disc.DataSha256) {
    throw ("Track 01 does not match Earthworm Jim 2 (Europe) {0}. Expected SHA-256 {1}." -f $Disc.Serial, $Disc.DataSha256)
}
Write-Ok "$($Disc.Serial), $tracks tracks, data track verified"
if ($ValidateOnly) {
    Write-Step 2 $Total 'Checking build environment'
    $free = (Get-PSDrive -Name ([IO.Path]::GetPathRoot($PublicRoot).Substring(0,1))).Free
    if ($free -lt 6GB) { throw ("At least 6 GB free are needed next to run.bat ({0:N1} GB free)." -f ($free / 1GB)) }
    Write-Ok ("{0:N1} GB free" -f ($free / 1GB))
    Write-Host ''; Write-Host 'Validation passed. Run run.bat without -ValidateOnly to build.' -ForegroundColor Green
    return
}

# ----------------------------------------------------------- 2 toolchain --
Write-Step 2 $Total 'Preparing the portable toolchain (clang, CMake, Ninja, Python)'
$tcZip = Join-Path $Downloads $Toolchain.Name
if ((Get-StateValue $State 'toolchain') -ne $Toolchain.Sha256 -or -not (Test-Path -LiteralPath (Join-Path $Tc 'bin\clang.exe'))) {
    Invoke-VerifiedDownload $Toolchain.Url $tcZip $Toolchain.Sha256
    Remove-BuildPath $Tc
    Write-Info 'extracting toolchain'
    Expand-Zip $tcZip $Tc
    if (-not (Test-Path -LiteralPath (Join-Path $Tc 'bin\clang.exe'))) {
        $inner = Get-ChildItem -LiteralPath $Tc -Directory | Where-Object { Test-Path (Join-Path $_.FullName 'bin\clang.exe') } | Select-Object -First 1
        if (-not $inner) { throw 'The toolchain archive does not contain bin\clang.exe.' }
        Get-ChildItem -LiteralPath $inner.FullName | Move-Item -Destination $Tc
        Remove-Item -LiteralPath $inner.FullName -Recurse -Force
    }
    Set-StateValue $State 'toolchain' $Toolchain.Sha256; Save-State $State
}
Write-Ok 'toolchain ready'

$env:PATH = "$Tc\bin;$Tc\python;$env:SystemRoot\System32;$env:SystemRoot;$env:SystemRoot\System32\WindowsPowerShell\v1.0"
$env:CC = Join-Path $Tc 'bin\clang.exe'
$env:CXX = Join-Path $Tc 'bin\clang++.exe'
$env:AR = Join-Path $Tc 'bin\llvm-ar.exe'
$env:RANLIB = Join-Path $Tc 'bin\llvm-ranlib.exe'
$env:RETCOMM_TOOLCHAIN_DIR = $Tc
$env:PYTHONHOME = ''; $env:PYTHONPATH = ''; $env:PYTHONNOUSERSITE = '1'
if (Test-Path (Join-Path $Tc 'deps\include\zlib.h')) { $env:ZLIB_ROOT = Join-Path $Tc 'deps' }
$sdl = Join-Path $Tc 'deps\lib\cmake\SDL3'
if (Test-Path $sdl) { $env:SDL3_DIR = $sdl }
$TmpDir = Join-Path $BuildRoot 'tmp'
New-Item -ItemType Directory -Force -Path $TmpDir | Out-Null
$env:TEMP = $TmpDir; $env:TMP = $TmpDir
$Cmake = Join-Path $Tc 'bin\cmake.exe'
$Python = Join-Path $Tc 'python\python.exe'

# ----------------------------------------------------------- 3 framework --
Write-Step 3 $Total 'Fetching psxrecomp and recomp-ui (pinned commits)'
$fwKey = ($Framework | ForEach-Object { $_.Commit }) -join ','
$fwRoot = Join-Path $BuildRoot 'framework'
if ((Get-StateValue $State 'framework') -ne $fwKey -or -not (Test-Path (Join-Path $fwRoot 'psxrecomp\psxrecomp_cli.py'))) {
    Remove-BuildPath $fwRoot
    foreach ($fw in $Framework) {
        $name = ($fw.Repo -split '/')[1]
        $zip = Join-Path $Downloads "$name-$($fw.Commit).zip"
        Invoke-VerifiedDownload "https://codeload.github.com/$($fw.Repo)/zip/$($fw.Commit)" $zip $fw.Sha256
        $tmp = Join-Path $BuildRoot "unpack-$name"
        Remove-BuildPath $tmp
        Expand-Zip $zip $tmp
        $top = Get-ChildItem -LiteralPath $tmp -Directory | Select-Object -First 1
        $dest = Join-Path $fwRoot $fw.Dest
        if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Recurse -Force }
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest) | Out-Null
        Move-Item -LiteralPath $top.FullName -Destination $dest
        Remove-BuildPath $tmp
    }
    Set-StateValue $State 'framework' $fwKey
    Set-StateValue $State 'emitters' $null
    Save-State $State
}
Write-Ok 'framework sources ready'

# ------------------------------------------------------------- 4 project --
Write-Step 4 $Total 'Assembling the project'
New-Item -ItemType Directory -Force -Path $Proj | Out-Null
Copy-Item -Path (Join-Path $PublicRoot 'project\*') -Destination $Proj -Recurse -Force
Copy-Item -LiteralPath (Join-Path $PublicRoot 'project\.recomp.json') -Destination $Proj -Force
foreach ($d in 'psxrecomp', 'recomp-ui') {
    $link = Join-Path $Proj $d
    if (-not (Test-Path -LiteralPath $link)) {
        # A junction keeps one copy of the framework and survives project refreshes.
        New-Item -ItemType Junction -Path $link -Target (Join-Path $fwRoot $d) | Out-Null
    }
}
New-Item -ItemType Directory -Force -Path (Join-Path $Proj 'assets') | Out-Null
Copy-Item -Path (Join-Path $fwRoot 'psxrecomp\assets\psxrecomp.*') -Destination (Join-Path $Proj 'assets') -Force
$cueFwd = $Cue -replace '\\', '/'
$toml = (Get-Content -LiteralPath (Join-Path $PublicRoot 'project\game.toml') -Raw).Replace('@DISC_CUE@', $cueFwd)
[IO.File]::WriteAllText((Join-Path $Proj 'game.toml'), $toml)
Write-Ok "project at $Proj"

# ------------------------------------------------------------ 5 emitters --
Write-Step 5 $Total 'Building the static recompiler (psxrecomp-game / psxrecomp-bios)'
$recBuild = Join-Path $Proj 'build-recompiler'
if ((Get-StateValue $State 'emitters') -ne $fwKey -or -not (Test-Path (Join-Path $recBuild 'psxrecomp-game.exe'))) {
    Invoke-Native $Cmake @('-S', (Join-Path $Proj 'psxrecomp\recompiler'), '-B', $recBuild, '-G', 'Ninja',
        '-DCMAKE_BUILD_TYPE=Release', "-DCMAKE_C_COMPILER=$($env:CC)", "-DCMAKE_CXX_COMPILER=$($env:CXX)",
        '-DPSXRECOMP_STATIC_CLI=ON') (Join-Path $Logs 'emitters-configure.log')
    Invoke-Native $Cmake @('--build', $recBuild, '--target', 'psxrecomp-game', 'psxrecomp-bios') (Join-Path $Logs 'emitters-build.log')
    Set-StateValue $State 'emitters' $fwKey
    Set-StateValue $State 'generated' $null
    Save-State $State
}
Write-Ok 'recompiler ready'

# ------------------------------------------------------------ 6 generate --
Write-Step 6 $Total 'Recompiling the game from your disc (loader + 19 game EXEs; this takes a while)'
$genKey = "$fwKey|$((Get-FileHash -Algorithm SHA256 (Join-Path $PublicRoot 'project\aot\overlays.json')).Hash)|$((Get-FileHash -Algorithm SHA256 (Join-Path $PublicRoot 'project\seeds\ghidra_funcs.txt')).Hash)"
$genDir = Join-Path $Proj 'generated'
if ($Force -or (Get-StateValue $State 'generated') -ne $genKey -or -not (Test-Path (Join-Path $genDir 'overlays_static.c'))) {
    Invoke-Native $Python @((Join-Path $Proj 'psxrecomp\psxrecomp_cli.py'), 'generate', '--config', (Join-Path $Proj 'game.toml'),
        '--project-root', $Proj, '--disc', $Cue) (Join-Path $Logs 'generate.log')
    if (-not (Test-Path (Join-Path $genDir 'overlays_static.c'))) {
        throw "Generation finished without generated\overlays_static.c. See $(Join-Path $Logs 'generate.log')."
    }
    Set-StateValue $State 'generated' $genKey
    Set-StateValue $State 'runtime' $null
    Save-State $State
}
Write-Ok 'game C generated (stays private on this PC)'

# ------------------------------------------------------------- 7 runtime --
Write-Step 7 $Total 'Compiling the native runtime'
$rtBuild = Join-Path $Proj 'build-release'
$rtKey = "$genKey|$Version"
if ($Force -or (Get-StateValue $State 'runtime') -ne $rtKey -or -not (Test-Path (Join-Path $rtBuild $ExeName))) {
    Invoke-Native $Cmake @('-S', $Proj, '-B', $rtBuild, '-G', 'Ninja', '-DCMAKE_BUILD_TYPE=Release',
        "-DCMAKE_C_COMPILER=$($env:CC)", "-DCMAKE_CXX_COMPILER=$($env:CXX)", '-DPSXRECOMP_REQUIRE_GAME_C=ON') (Join-Path $Logs 'runtime-configure.log')
    # The generated game C comes in very large units; one clang -O3 per core can
    # exhaust RAM. Allow about 4 GB per parallel job, never more than the cores.
    $ramGb = [Math]::Floor((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB)
    $jobs = [Math]::Max(1, [Math]::Min([Environment]::ProcessorCount, [Math]::Floor($ramGb / 4)))
    Write-Info "compiling with $jobs parallel jobs ($ramGb GB RAM)"
    Invoke-Native $Cmake @('--build', $rtBuild, '--target', 'psx-runtime', '-j', "$jobs") (Join-Path $Logs 'runtime-build.log')
    Set-StateValue $State 'runtime' $rtKey; Save-State $State
}
Write-Ok 'runtime built'

# ------------------------------------------------------------- 8 install --
Write-Step 8 $Total 'Installing into out\'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
Copy-Item -LiteralPath (Join-Path $rtBuild $ExeName) -Destination $OutDir -Force
foreach ($d in 'bios', 'assets', 'mods') {
    $src = Join-Path $rtBuild $d
    if (Test-Path -LiteralPath $src) {
        $dst = Join-Path $OutDir $d
        if (Test-Path -LiteralPath $dst) { Remove-Item -LiteralPath $dst -Recurse -Force }
        Copy-Item -LiteralPath $src -Destination $dst -Recurse -Force
    }
}
foreach ($f in 'game.toml', 'game_options.toml', 'psx_game_version.txt') {
    $src = Join-Path $rtBuild $f
    if (Test-Path -LiteralPath $src) { Copy-Item -LiteralPath $src -Destination $OutDir -Force }
}
Set-Content -LiteralPath (Join-Path $OutDir 'version.txt') -Value $Version -Encoding ASCII
Write-Progress -Activity 'Earthworm Jim 2 Recompiled' -Completed
Write-Ok "installed: $(Join-Path $OutDir $ExeName)"
