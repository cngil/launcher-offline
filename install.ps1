<#
.SYNOPSIS
Installs or updates Launcher Offline for the current user and opens it.

    irm https://raw.githubusercontent.com/cngil/launcher-offline/main/install.ps1 | iex

Copies the files to %LOCALAPPDATA%\LauncherOffline and adds a Start menu and a
desktop shortcut. Nothing else is written. Run it again to update.
#>
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$repo    = 'cngil/launcher-offline'
$dest    = Join-Path $env:LOCALAPPDATA 'LauncherOffline'
$zip     = Join-Path $env:TEMP 'launcher-offline.zip'
$extract = Join-Path $env:TEMP ('launcher-offline-' + [guid]::NewGuid().ToString('N'))

Write-Host "Downloading $repo ..."
Invoke-WebRequest "https://github.com/$repo/archive/refs/heads/main.zip" -OutFile $zip -UseBasicParsing
Expand-Archive -LiteralPath $zip -DestinationPath $extract -Force
$source = Get-ChildItem -LiteralPath $extract -Directory | Select-Object -First 1

if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Recurse -Force }
Move-Item -LiteralPath $source.FullName -Destination $dest
Remove-Item -LiteralPath $zip, $extract -Recurse -Force -ErrorAction SilentlyContinue

$shell = New-Object -ComObject WScript.Shell
foreach ($folder in [Environment]::GetFolderPath('Programs'), [Environment]::GetFolderPath('Desktop')) {
    $link = $shell.CreateShortcut((Join-Path $folder 'Launcher Offline.lnk'))
    $link.TargetPath       = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $link.Arguments        = "-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$dest\src\LauncherOffline.ps1`""
    $link.WorkingDirectory = $dest
    $link.IconLocation     = Join-Path $dest 'assets\icon.ico'
    $link.Description      = 'Play your games with launchers in offline mode'
    $link.Save()
}

Write-Host "Installed to $dest"
Start-Process -FilePath (Join-Path $dest 'LauncherOffline.cmd')
