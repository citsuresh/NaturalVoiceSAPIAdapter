# Local build and setup (Windows 11)

Personal notes and helper scripts for building NaturalVoiceSAPIAdapter v0.2.11 from source and
registering it without the released installer or zip. Nothing in the adapter's own source is changed.
Built and verified on Windows 11 with Visual Studio (v145 toolset) on 2026-11-12.

The released binaries have been reported as false positives by antivirus products
(see upstream issues #122, #96, #107, #87). A local build avoids the downloaded-file mark and the
released hash, but an unsigned build is not guaranteed to stay clean.

## Prerequisites

- Visual Studio 2026 with the **Desktop development with C++** workload: MSVC v145 build tools for
  x86/x64, ATL, and a Windows 11 SDK (10.0.26100.0 was used). Visual Studio 2022 has only v143 and
  cannot build these projects as configured.
- `nuget.exe` (for example `winget install Microsoft.NuGet`).

## Build

```powershell
git clone --recurse-submodules https://github.com/citsuresh/NaturalVoiceSAPIAdapter.git
cd NaturalVoiceSAPIAdapter
git checkout v0.2.11
git submodule update --init --recursive
```

The main project registers its output with `regsvr32` after each build, which fails when not elevated
(MSB8011). To build without registering, temporarily change `<RegisterOutput>true</RegisterOutput>`
to `false` in `NaturalVoiceSAPIAdapter\NaturalVoiceSAPIAdapter.vcxproj`, build, then revert it with
`git checkout -- NaturalVoiceSAPIAdapter\NaturalVoiceSAPIAdapter.vcxproj`.

```powershell
$msbuild = 'C:\Program Files\Microsoft Visual Studio\<version>\<edition>\MSBuild\Current\Bin\MSBuild.exe'
& $msbuild NaturalVoiceSAPIAdapter.sln /p:Configuration=Release /p:Platform=x64 /t:NaturalVoiceSAPIAdapter
& $msbuild NaturalVoiceSAPIAdapter.sln /p:Configuration=Release /p:Platform=x86 /t:NaturalVoiceSAPIAdapter
```

Notes:

- Build only the `NaturalVoiceSAPIAdapter` target. A solution-level `/t:Rebuild` deletes the output and
  fails on the installer project's missing YY-Thunks package.
- Output is in `out\x64` and `out\x86`.
- On Windows 10 build 17763 and later, the Azure Speech SDK shim and SpeechSDKPatcher are not needed.
- Optional installer UI: run `nuget restore Installer -SolutionDirectory .`, then build the `Installer`
  project for `x86`.

## Install

Copy the following into one permanent folder, for example `C:\Tools\NaturalVoiceSAPIAdapter`:

```
x64\   all files from out\x64 except the codec DLL (see below)
x86\   all files from out\x86 except the codec DLL
LICENSE.txt
Configure.ps1, Register.bat, Unregister.bat   (from this folder)
```

The codec DLL and `TtsApplication.exe` were left out (the project's own CI also excludes the codec DLL).
The registry stores absolute paths, so run `Unregister.bat` before moving or deleting the folder.

1. Run `Register.bat` as administrator. It registers the 64-bit and 32-bit DLLs.
2. Run `Configure.ps1` (right-click, Run with PowerShell) to check registration and change settings.

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
