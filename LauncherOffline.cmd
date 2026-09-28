@echo off
rem Double-click to open Launcher Offline. No install needed.
rem The console starts minimized rather than hidden: antivirus heuristics flag hidden PowerShell launches.
start "" /min powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0src\LauncherOffline.ps1"
