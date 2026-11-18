@echo off
title Uninstall Hundred Face
powershell.exe -NoLogo -NoProfile -Command "$root = Join-Path $env:LOCALAPPDATA 'Hundred Face'; $startup = Join-Path ([Environment]::GetFolderPath('Startup')) 'Hundred Face.vbs'; if (Test-Path -LiteralPath $startup) { Remove-Item -LiteralPath $startup -ErrorAction Stop }; if (Test-Path -LiteralPath $root) { New-Item -ItemType File -Path (Join-Path $root 'disabled') -Force | Out-Null; $secret = Join-Path $root 'webhook.txt'; if (Test-Path -LiteralPath $secret) { Remove-Item -LiteralPath $secret -ErrorAction Stop } }; Write-Host 'Hundred Face has been disabled and its webhook removed. Local session history is kept in' $root"
pause
