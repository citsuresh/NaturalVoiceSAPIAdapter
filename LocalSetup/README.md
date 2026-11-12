# Local build and setup (Windows 11)

Personal notes and helper scripts for building NaturalVoiceSAPIAdapter v0.2.11 from source and
registering it without the released installer or zip. The adapter's source code is not changed; the only
additions outside this folder are `Directory.Build.targets` (see "About this fork") and a note at the top of the root README.
Built and verified on Windows 11 with Visual Studio (v145 toolset) on 2026-11-12.

The released binaries have been reported as false positives by antivirus products
(see upstream issues #122, #96, #107, #87). A local build avoids the downloaded-file mark and the
released hash, but an unsigned build is not guaranteed to stay clean.

## Quick start

Opening the solution in Visual Studio and building it there is **not** required. Use these three steps
from a normal (non-administrator) PowerShell window:

```powershell
# 1. Get the code
git clone --recurse-submodules https://github.com/citsuresh/NaturalVoiceSAPIAdapter.git
cd NaturalVoiceSAPIAdapter\LocalSetup

# 2. Build x64 and x86 and copy the result to a permanent install folder
.\Build-And-Deploy.ps1

# 3. Register it, from the install folder (not from the repository)
cd C:\Docs\Tools\NaturalVoiceSAPIAdapter      # or the folder you chose in step 2
.\Configure.ps1                               # menu; offers to register, UAC prompt appears
```

Step 2 asks for the install folder (Enter accepts `C:\Docs\Tools\NaturalVoiceSAPIAdapter`). Step 3 can
also be `Register.bat`, run as administrator. Building never registers anything.

## Prerequisites

- Git, and a PowerShell window with the execution policy allowing local scripts
  (`Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` if scripts are blocked).
- Visual Studio 2026 with the **Desktop development with C++** workload: MSVC v145 build tools for
  x86/x64, ATL, and a Windows 11 SDK (10.0.26100.0 was used). Visual Studio 2022 has only v143 and
  cannot build these projects as configured.
- `nuget.exe` on `PATH` (for example `winget install Microsoft.NuGet`).

## Build-And-Deploy.ps1

Run from `LocalSetup`. It finds MSBuild through `vswhere`, initialises the submodules, restores the
NuGet packages, builds `Release` for x64 and x86 (about 3 to 5 minutes the first time), and copies the
result to the install folder: `x64\`, `x86\`, `LICENSE.txt`, `Configure.ps1`, `Register.bat`,
`Unregister.bat`. The codec DLL is left out (it can cause a "GStreamer DLL not found" error; the
project's CI also excludes it). It never registers anything and never touches the registry.

| Option | Meaning |
| --- | --- |
| `-Target <folder>` | Install folder. If omitted you are asked (default `C:\Docs\Tools\NaturalVoiceSAPIAdapter`). |
| `-SkipBuild` | Copy what is already in `out\x64` and `out\x86` without building. |
| `-Configuration <name>` | Build configuration. Default `Release`. |
| `-Force` | Do not ask for confirmation. |
| `-WhatIf` | Show what would be built and copied, and change nothing. |

```powershell
.\Build-And-Deploy.ps1                                   # prompts for the folder
.\Build-And-Deploy.ps1 -Target D:\Tools\NVSA -Force      # no prompts
.\Build-And-Deploy.ps1 -Target D:\Tools\NVSA -SkipBuild  # redeploy the last build
.\Build-And-Deploy.ps1 -WhatIf                            # dry run
```

If the DLLs in the target folder are currently registered, the script stops and asks you to run
`Unregister.bat` first (Windows locks registered DLLs, and the registry points at that folder). To
update an installed copy: `Unregister.bat`, run the script again, then register again.

### About this fork

This fork is upstream v0.2.11 (plus one later upstream commit that only touches release notes) with two
additions: this `LocalSetup\` folder and a repo-root `Directory.Build.targets`. No upstream file is
modified, so upstream updates can be merged without conflicts.

Upstream builds run `regsvr32` on the output after every build, which fails when not elevated
(MSB8011) and, when elevated, registers the DLL from `out\`. `Directory.Build.targets` turns that off
only when the build is given `/p:NvsaNoRegister=true`, which `Build-And-Deploy.ps1` always passes. A
build started that way never registers anything; registration happens only through `Register.bat`,
`Configure.ps1` or the installer. A plain build (for example F5 in Visual Studio) behaves exactly as
upstream.

### Building by hand (not needed if you use the script)

```powershell
$msbuild = 'C:\Program Files\Microsoft Visual Studio\<version>\<edition>\MSBuild\Current\Bin\MSBuild.exe'
nuget restore NaturalVoiceSAPIAdapter.sln
& $msbuild NaturalVoiceSAPIAdapter.sln /p:Configuration=Release /p:Platform=x64 /t:NaturalVoiceSAPIAdapter /p:NvsaNoRegister=true "/p:OutDir=$PWD\out\x64\\"
& $msbuild NaturalVoiceSAPIAdapter.sln /p:Configuration=Release /p:Platform=x86 /t:NaturalVoiceSAPIAdapter /p:NvsaNoRegister=true "/p:OutDir=$PWD\out\x86\\"
```

Notes:

- Build only the `NaturalVoiceSAPIAdapter` target. A solution-level `/t:Rebuild` deletes the output and
  fails on the installer project's missing YY-Thunks package.
- Output is in `out\x64` and `out\x86` (the `OutDir` setting above; without it the output goes to
  `x64\Release` and `Release`).
- On Windows 10 build 17763 and later, the Azure Speech SDK shim and SpeechSDKPatcher are not needed.
- Optional installer UI: run `nuget restore Installer -SolutionDirectory .`, then build the `Installer`
  project for `x86`.

## Register and uninstall

Do this from the install folder that `Build-And-Deploy.ps1` filled, not from the repository:

- **Register:** run `Register.bat` as administrator (registers the 64-bit and 32-bit DLLs), or run
  `Configure.ps1`, which shows the status on start and offers to register what is missing.
- **Settings:** run `Configure.ps1` at any time (see below).
- **Uninstall:** run `Unregister.bat` as administrator. Do this before moving or deleting the install
  folder or before redeploying into it: the registry stores absolute paths. Per-user settings stay in
  `HKCU\Software\NaturalVoiceSAPIAdapter` and the cache in `%LOCALAPPDATA%\NaturalVoiceSAPIAdapter`;
  delete them yourself for a clean removal.

`TtsApplication.exe` (flagged by Defender in the released zip) is not part of this build or deploy.

## Configure.ps1

On start it shows whether the 64-bit and 32-bit DLLs are registered and offers to register any that
are missing. Settings are per-user (HKCU) and need no administrator rights, except the
register/unregister actions, which prompt for elevation. The menu covers:

- register/unregister the 64-bit and 32-bit DLLs
- toggle Narrator natural voices, Edge voices and Azure voices
- local Narrator voice folder path
- Azure key (input is masked) and region
- Edge voice languages
- log level, and opening the log/cache folder (`%LOCALAPPDATA%\NaturalVoiceSAPIAdapter`)
- list the installed SAPI voices
- open the classic Text to Speech dialog (`control /name Microsoft.TextToSpeech`) and the modern
  Speech settings page (`ms-settings:speech`)

The Azure key is stored by the adapter in plain text under
`HKCU\Software\NaturalVoiceSAPIAdapter\Enumerator`, as with the official installer. It is not kept in
any script here.

Not covered compared with the installer UI: the searchable language picker, the Narrator settings and
voice-download links, the Installed apps uninstall entry, and the installer's own language/About
dialogs.

## Seeing the voices

After registration the new voices appear in SAPI 5 applications and in the classic Text to Speech
dialog. The modern Settings > Speech page lists only the built-in OneCore voices, not SAPI 5 voices.
