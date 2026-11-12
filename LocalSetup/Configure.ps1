<#
.SYNOPSIS
  Menu-driven replacement for the NaturalVoiceSAPIAdapter installer UI (v0.2.11).
.DESCRIPTION
  Mirrors the installer's options: install/uninstall (32/64-bit), voice sources, Azure key,
  Edge language filter, log level and log/cache folder. Settings live in
  HKCU\Software\NaturalVoiceSAPIAdapter and need no admin rights; only register/unregister
  elevates (UAC prompt). Do not move this folder while the adapter is registered.
  Modifies the registry (HKCU settings; HKLM COM registration via regsvr32).
#>
$ErrorActionPreference = 'Stop'
$root   = $PSScriptRoot
$base   = 'HKCU:\Software\NaturalVoiceSAPIAdapter'
$enum   = "$base\Enumerator"
$clsid  = '{013ab33b-ad1a-401c-8bee-f6e2b046a94e}'
$logNames = 'Trace','Debug','Info','Warning','Error','Critical','Off'

function Get-Setting($path, $name, $default = $null) {
    $p = Get-ItemProperty -Path $path -ErrorAction SilentlyContinue
    if ($p -and $null -ne $p.$name) { return $p.$name }
    return $default
}
function Set-Setting($path, $name, $value, $type = 'DWord') {
    if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
    Set-ItemProperty -Path $path -Name $name -Value $value -Type $type
}

function Get-InstalledPath([bool]$is64) {
    $view = if ($is64) { 'Registry64' } else { 'Registry32' }
    $hklm = [Microsoft.Win32.RegistryKey]::OpenBaseKey('LocalMachine', $view)
    $k = $hklm.OpenSubKey("SOFTWARE\Classes\CLSID\$clsid\InprocServer32")
    if ($k) { $v = $k.GetValue(''); $k.Close(); return $v }
    return $null
}

function Invoke-Regsvr([bool]$is64, [bool]$unregister) {
    $exe = if ($is64) { "$env:WINDIR\System32\regsvr32.exe" } else { "$env:WINDIR\SysWOW64\regsvr32.exe" }
    $dll = Join-Path $root ($(if ($is64) { 'x64' } else { 'x86' }) + '\NaturalVoiceSAPIAdapter.dll')
    if (-not $unregister -and -not (Test-Path $dll)) { Write-Host "Missing: $dll" -ForegroundColor Red; return }
    if ($unregister) { $dll = Get-InstalledPath $is64; if (-not $dll) { Write-Host 'Not registered.'; return } }
    $args = @('/s'); if ($unregister) { $args = @('/u','/s') }
    $args += "`"$dll`""
    $admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole('Administrator')
    try {
        if ($admin) { $p = Start-Process $exe -ArgumentList $args -Wait -PassThru }
        else        { $p = Start-Process $exe -ArgumentList $args -Wait -PassThru -Verb RunAs }
        if ($p.ExitCode -eq 0) { Write-Host 'Done.' -ForegroundColor Green } else { Write-Host "regsvr32 failed, exit code $($p.ExitCode)" -ForegroundColor Red }
    } catch { Write-Host "Cancelled or failed: $($_.Exception.Message)" -ForegroundColor Yellow }
}

function Show-Status {
    foreach ($is64 in $true, $false) {
        $label = if ($is64) { '64-bit' } else { '32-bit' }
        $path = Get-InstalledPath $is64
        if ($path) {
            $note = if (Test-Path $path) { 'file present' } else { 'FILE MISSING' }
            Write-Host ("{0}: Installed -> {1} ({2})" -f $label, $path, $note)
        } else { Write-Host "${label}: Not installed" }
    }
}

function Show-Languages {
    if (Get-Setting $enum 'EdgeVoiceAllLanguages' 0) { return 'All supported languages' }
    $l = @(Get-Setting $enum 'EdgeVoiceLanguages' @()) | Where-Object { $_ }
    if ($l.Count -eq 0) { return "User's preferred languages" }
    return ($l -join ', ')
}

function Show-Settings {
    $nar  = -not (Get-Setting $enum 'NoNarratorVoices' 0)
    $edge = -not (Get-Setting $enum 'NoEdgeVoices' 0)
    $hasKey = [bool](Get-Setting $enum 'AzureVoiceKey' '') -or [bool](Get-Setting $enum 'AzureVoiceRegion' '')
    $az   = (-not (Get-Setting $enum 'NoAzureVoices' 0)) -and $hasKey
    $lv   = [Math]::Min([Math]::Max([int](Get-Setting $base 'LogLevel' 2),0),6)
    Write-Host ("Narrator natural voices : {0}" -f $(if ($nar) {'ON'} else {'off'}))
    $vp = Get-Setting $enum 'NarratorVoicePath' ''
        Write-Host ("  Local voice path      : {0}" -f $(if ($vp) { $vp } else { '(default)' }))
    Write-Host ("Edge online voices      : {0}" -f $(if ($edge) {'ON'} else {'off'}))
    Write-Host ("Azure online voices     : {0}" -f $(if ($az) {'ON'} else {'off'}))
    Write-Host ("  Azure key / region    : {0} / {1}" -f $(if (Get-Setting $enum 'AzureVoiceKey' '') {'(set)'} else {'(not set)'}), $(Get-Setting $enum 'AzureVoiceRegion' '(not set)'))
    Write-Host ("Included languages      : {0}" -f (Show-Languages))
    Write-Host ("  All multilingual      : {0}" -f $(if (Get-Setting $enum 'EdgeVoiceAllMultilingual' 0) {'yes'} else {'no'}))
    Write-Host ("Log level               : {0}" -f $logNames[$lv])
}

function Toggle-NoValue($name, $label) {
    $disabled = [bool](Get-Setting $enum $name 0)
    Set-Setting $enum $name ([int](-not $disabled))
    Write-Host ("{0}: now {1}" -f $label, $(if ($disabled) {'ON'} else {'off'}))
}

function Set-AzureKey {
    Write-Host 'Azure Portal > your Speech resource > Keys and Endpoint. Leave blank to keep the current value.'
    $sec = Read-Host 'Key' -AsSecureString
    $key = [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
    $region = Read-Host 'Region (e.g. eastus)'
    if ($key)    { Set-Setting $enum 'AzureVoiceKey' $key 'String' }
    if ($region) { Set-Setting $enum 'AzureVoiceRegion' $region 'String' }
    Write-Host 'Saved (the key is stored as plain text in your user registry, as the original installer does).'
}

function Set-LanguageMenu {
    Write-Host "Current: $(Show-Languages)"
    Write-Host '1) All supported languages  2) User preferred languages  3) Custom list  4) Toggle all-multilingual  0) Back'
    switch (Read-Host 'Choice') {
        '1' { Set-Setting $enum 'EdgeVoiceAllLanguages' 1 }
        '2' { Set-Setting $enum 'EdgeVoiceAllLanguages' 0; Set-Setting $enum 'EdgeVoiceLanguages' ([string[]]@()) 'MultiString' }
        '3' {
            $in = Read-Host 'Comma-separated language tags, e.g. en-US,en-GB,hi-IN'
            $l = [string[]]@($in -split '[,;\s]+' | Where-Object { $_ })
            if ($l.Count -gt 0) { Set-Setting $enum 'EdgeVoiceAllLanguages' 0; Set-Setting $enum 'EdgeVoiceLanguages' $l 'MultiString' }
        }
        '4' { Set-Setting $enum 'EdgeVoiceAllMultilingual' ([int](-not (Get-Setting $enum 'EdgeVoiceAllMultilingual' 0))) }
    }
}

function Set-LogLevel {
    for ($i = 0; $i -lt 7; $i++) { Write-Host "  $i) $($logNames[$i])" }
    $v = Read-Host 'Log level 0-6'
    if ($v -match '^[0-6]$') { Set-Setting $base 'LogLevel' ([int]$v) }
}

function Set-VoicePath {
    $p = Read-Host 'Local voice folder (ASCII path with voice subfolders; blank = default)'
    if ($p) { Set-Setting $enum 'NarratorVoicePath' $p 'String' }
    elseif (Get-ItemProperty $enum -Name NarratorVoicePath -ErrorAction SilentlyContinue) { Remove-ItemProperty $enum -Name NarratorVoicePath }
}

function Show-Voices {
    Add-Type -AssemblyName System.Speech
    $s = New-Object System.Speech.Synthesis.SpeechSynthesizer
    $s.GetInstalledVoices() | ForEach-Object { '{0} | {1}' -f $_.VoiceInfo.Name, $_.VoiceInfo.Culture }
    Write-Host "(this PowerShell is $(if ([Environment]::Is64BitProcess) {'64'} else {'32'})-bit)"
}

# Startup: detect registration and offer to register whatever is missing
Write-Host "`n=== NaturalVoiceSAPIAdapter: registration check ===" -ForegroundColor Cyan
Show-Status
foreach ($is64 in $true, $false) {
    if (-not (Get-InstalledPath $is64)) {
        $label = if ($is64) { '64-bit' } else { '32-bit' }
        if ((Read-Host "$label is not registered. Register it now? (Y/N)") -match '^[Yy]') { Invoke-Regsvr $is64 $false }
    }
}

while ($true) {
    Write-Host "`n=== NaturalVoiceSAPIAdapter ===" -ForegroundColor Cyan
    Show-Status; Write-Host '---'; Show-Settings
    Write-Host @'

 1) Register 64-bit     2) Unregister 64-bit
 3) Register 32-bit     4) Unregister 32-bit
 5) Toggle Narrator voices        6) Set local voice path
 7) Toggle Edge online voices     8) Toggle Azure online voices
 9) Set Azure key and region     10) Change included languages
11) Set log level                12) Open log and cache folder
13) List installed voices        14) Open classic Text to Speech (SAPI)
15) Open Windows Speech settings   Q) Quit
'@
    switch ((Read-Host 'Choice').ToUpper()) {
        '1'  { Invoke-Regsvr $true  $false }
        '2'  { Invoke-Regsvr $true  $true }
        '3'  { Invoke-Regsvr $false $false }
        '4'  { Invoke-Regsvr $false $true }
        '5'  { Toggle-NoValue 'NoNarratorVoices' 'Narrator voices' }
        '6'  { Set-VoicePath }
        '7'  { Toggle-NoValue 'NoEdgeVoices' 'Edge voices' }
        '8'  { Toggle-NoValue 'NoAzureVoices' 'Azure voices' }
        '9'  { Set-AzureKey }
        '10' { Set-LanguageMenu }
        '11' { Set-LogLevel }
        '12' { $d = "$env:LOCALAPPDATA\NaturalVoiceSAPIAdapter"; if (Test-Path $d) { Start-Process explorer.exe $d } else { Write-Host "Not created yet: $d" } }
        '13' { Show-Voices }
        '14' { Start-Process "$env:WINDIR\System32\control.exe" -ArgumentList '/name','Microsoft.TextToSpeech' }
        '15' { Start-Process 'ms-settings:speech' }
        'Q'  { return }
    }
}
