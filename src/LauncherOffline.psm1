# Core logic shared by the GUI, the CLI and the tests. Entry point: LauncherOffline.ps1
Set-StrictMode -Version 2.0

$script:ModuleRoot   = $PSScriptRoot
$script:EntryScript  = Join-Path $PSScriptRoot 'LauncherOffline.ps1'
$script:LaunchersDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'launchers'
$script:LocalesDir   = Join-Path (Split-Path $PSScriptRoot -Parent) 'locales'
$script:RuleGroup    = 'LauncherOffline'
$script:ProjectUrl   = 'https://github.com/cngil/launcher-offline'

function Get-LOProjectUrl { $script:ProjectUrl }

foreach ($file in Get-ChildItem -Path (Join-Path $PSScriptRoot 'lib') -Filter '*.ps1') {
    . $file.FullName
}

Export-ModuleMember -Function *
