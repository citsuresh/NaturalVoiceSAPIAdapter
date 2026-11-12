@echo off
rem Registers the locally built NaturalVoiceSAPIAdapter (x64 and x86) as SAPI 5 voices.
rem Run from an elevated prompt (right-click > Run as administrator).
rem Do not move or delete this folder while registered; run Unregister.bat first.
net session >nul 2>&1
if errorlevel 1 (
    echo This script must be run as administrator.
    pause
    exit /b 1
)
set "D=%~dp0"
echo Registering 64-bit...
"%SystemRoot%\System32\regsvr32.exe" /s "%D%x64\NaturalVoiceSAPIAdapter.dll"
if errorlevel 1 ( echo 64-bit registration FAILED, code %errorlevel% ) else ( echo 64-bit registered. )
echo Registering 32-bit...
"%SystemRoot%\SysWOW64\regsvr32.exe" /s "%D%x86\NaturalVoiceSAPIAdapter.dll"
if errorlevel 1 ( echo 32-bit registration FAILED, code %errorlevel% ) else ( echo 32-bit registered. )
pause
