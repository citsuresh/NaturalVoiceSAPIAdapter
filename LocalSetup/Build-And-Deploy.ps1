<#
.SYNOPSIS
    Builds NaturalVoiceSAPIAdapter (x64 and x86) and copies the result to an install folder.

.DESCRIPTION
    1. Optionally builds the Release x64 and x86 DLLs with MSBuild (found through vswhere).
    2. Copies the DLLs (without the codec DLL, which can cause a 'GStreamer DLL not found' error)
       to <Target>\x64 and <Target>\x86, plus LICENSE.txt, Configure.ps1, Register.bat and
       Unregister.bat.
    It never registers anything. Run Register.bat or Configure.ps1 from the install folder afterwards.
    If a DLL in the target is currently registered, the script stops: run Unregister.bat first.

.PARAMETER Target
    Install folder. If omitted, you are prompted (Enter accepts the default).

.PARAMETER SkipBuild
    Copy what is already in out\x64 and out\x86 without building.

.PARAMETER Configuration
    Build configuration. Default Release.

.PARAMETER Force
    Do not ask for confirmation.

.PARAMETER WhatIf
    Show what would be built and copied without doing it.

.EXAMPLE
    .\Build-And-Deploy.ps1
.EXAMPLE
    .\Build-And-Deploy.ps1 -Target C:\Tools\NaturalVoiceSAPIAdapter -SkipBuild -Force
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$Target,
    [switch]$SkipBuild,
    [string]$Configuration = 'Release',
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$repo       = Split-Path $PSScriptRoot -Parent
$defaultDir = 'C:\Docs\Tools\NaturalVoiceSAPIAdapter'
$clsid      = '{013ab33b-ad1a-401c-8bee-f6e2b046a94e}'
$excluded   = 'Microsoft.CognitiveServices.Speech.extension.codec.dll'
$archs      = @(
    @{ Name = 'x64'; Platform = 'x64' },
    @{ Name = 'x86'; Platform = 'x86' }
)

if (-not $Target) {
    $answer = Read-Host "Install folder [$defaultDir]"
    $Target = if ([string]::IsNullOrWhiteSpace($answer)) { $defaultDir } else { $answer.Trim('"') }
}
$Target = [IO.Path]::GetFullPath($Target)

function Get-RegisteredPath([string]$view) {
    $key = if ($view -eq 'x86') { "HKLM:\SOFTWARE\Classes\WOW6432Node\CLSID\$clsid\InprocServer32" }
           else { "HKLM:\SOFTWARE\Classes\CLSID\$clsid\InprocServer32" }
    if (Test-Path $key) { (Get-ItemProperty $key).'(default)' } else { $null }
}

foreach ($a in $archs) {
    $reg = Get-RegisteredPath $a.Name
    if (-not $reg) { continue }
    $mine = Join-Path $Target "$($a.Name)\NaturalVoiceSAPIAdapter.dll"
    if ([string]::Equals($reg, $mine, 'OrdinalIgnoreCase')) {
        throw "The $($a.Name) DLL in the target is registered ($reg). Run Unregister.bat first, then rerun this script."
    }
    Write-Warning "$($a.Name) is currently registered from $reg (not the target). Registering later will replace that."
}

Write-Host "Repository : $repo"
Write-Host "Target     : $Target"
Write-Host ("Build      : " + $(if ($SkipBuild) { 'skipped (copy existing out\ output)' } else { "$Configuration x64 and x86" }))
if (-not $Force -and -not $WhatIfPreference) {
    if ((Read-Host 'Continue? (Y/N)') -notmatch '^[Yy]') { Write-Host 'Cancelled.'; return }
}

if (-not $SkipBuild) {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path $vswhere)) { throw 'vswhere.exe not found. Install Visual Studio with the Desktop C++ workload, or use -SkipBuild.' }
    $msbuild = & $vswhere -latest -prerelease -products * -requires Microsoft.Component.MSBuild -find 'MSBuild\**\Bin\MSBuild.exe' | Select-Object -First 1
    if (-not $msbuild) { throw 'MSBuild not found through vswhere.' }
    Write-Host "MSBuild    : $msbuild"

    if ($PSCmdlet.ShouldProcess($repo, 'Initialize submodules')) {
        Push-Location $repo
        try {
            $ErrorActionPreference = 'Continue'
            & git submodule update --init --recursive 2>&1 | ForEach-Object { "$_" }
            if ($LASTEXITCODE -ne 0) { throw 'git submodule update failed.' }
        }
        finally { $ErrorActionPreference = 'Stop'; Pop-Location }
    }

    # msbuild -restore does not restore packages.config projects, so use nuget.exe
    $nuget = (Get-Command nuget.exe -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source)
    if (-not $nuget) {
        $nuget = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Filter nuget.exe -Recurse -ErrorAction SilentlyContinue |
            Select-Object -First 1 -ExpandProperty FullName
    }
    if (-not $nuget) { throw 'nuget.exe not found. Install it (winget install Microsoft.NuGet) or add it to PATH.' }
    if ($PSCmdlet.ShouldProcess($repo, 'Restore NuGet packages')) {
        Write-Host "`nRestoring NuGet packages ($nuget)..."
        $ErrorActionPreference = 'Continue'
        & $nuget restore (Join-Path $repo 'NaturalVoiceSAPIAdapter.sln') -NonInteractive 2>&1 | ForEach-Object { "$_" }
        $restoreExit = $LASTEXITCODE
        $ErrorActionPreference = 'Stop'
        if ($restoreExit -ne 0) { throw "NuGet restore failed (exit code $restoreExit)." }
    }

    foreach ($a in $archs) {
        if ($PSCmdlet.ShouldProcess("$($a.Name) $Configuration", 'Build')) {
            Write-Host "`nBuilding $($a.Name)..."
            $ErrorActionPreference = 'Continue'
            & $msbuild (Join-Path $repo 'NaturalVoiceSAPIAdapter.sln') -nologo -v:minimal `
                "/p:Configuration=$Configuration" "/p:Platform=$($a.Platform)" "/p:OutDir=$repo\out\$($a.Name)\\" '/p:NvsaNoRegister=true' `
                '/t:NaturalVoiceSAPIAdapter' 2>&1 | ForEach-Object { "$_" }
            $buildExit = $LASTEXITCODE
            $ErrorActionPreference = 'Stop'
            if ($buildExit -ne 0) { throw "Build failed for $($a.Name) (exit code $buildExit)." }
        }
    }
}

foreach ($a in $archs) {
    $src = Join-Path $repo "out\$($a.Name)"
    if (-not $WhatIfPreference -and -not (Test-Path (Join-Path $src 'NaturalVoiceSAPIAdapter.dll'))) {
        throw "$src\NaturalVoiceSAPIAdapter.dll not found. Build first (run without -SkipBuild)."
    }
    $dst = Join-Path $Target $a.Name
    if ($PSCmdlet.ShouldProcess($dst, "Copy DLLs from $src")) {
        New-Item -ItemType Directory -Path $dst -Force | Out-Null
        $files = Get-ChildItem $src -Filter *.dll -File | Where-Object { $_.Name -ne $excluded }
        Copy-Item $files.FullName -Destination $dst -Force
        Write-Host "$($a.Name): copied $($files.Count) DLLs to $dst"
    }
}

foreach ($f in @(@{ From = Join-Path $repo 'LICENSE.txt' }, @{ From = Join-Path $PSScriptRoot 'Configure.ps1' },
                 @{ From = Join-Path $PSScriptRoot 'Register.bat' }, @{ From = Join-Path $PSScriptRoot 'Unregister.bat' })) {
    if ($PSCmdlet.ShouldProcess($Target, "Copy $(Split-Path $f.From -Leaf)")) {
        New-Item -ItemType Directory -Path $Target -Force | Out-Null
        Copy-Item $f.From -Destination $Target -Force
    }
}

if (-not $WhatIfPreference) {
    Write-Host "`nDone. Next: run Register.bat as administrator, or Configure.ps1, from $Target"
}
