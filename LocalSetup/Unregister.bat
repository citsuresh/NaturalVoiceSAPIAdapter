@echo off
rem Unregisters NaturalVoiceSAPIAdapter (x64 and x86). Run from an elevated prompt.
net session >nul 2>&1
if errorlevel 1 (
    echo This script must be run as administrator.
    pause
    exit /b 1
)
set "D=%~dp0"
"%SystemRoot%\System32\regsvr32.exe" /u /s "%D%x64\NaturalVoiceSAPIAdapter.dll"
if errorlevel 1 ( echo 64-bit unregister FAILED, code %errorlevel% ) else ( echo 64-bit unregistered. )
"%SystemRoot%\SysWOW64\regsvr32.exe" /u /s "%D%x86\NaturalVoiceSAPIAdapter.dll"
if errorlevel 1 ( echo 32-bit unregister FAILED, code %errorlevel% ) else ( echo 32-bit unregistered. )
pause
