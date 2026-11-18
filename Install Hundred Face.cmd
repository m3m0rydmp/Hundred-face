@echo off
title Hundred Face Setup
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Setup.ps1"
if errorlevel 1 echo Setup did not finish.
pause
