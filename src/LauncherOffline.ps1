<#
.SYNOPSIS
Launcher Offline: blocks game launchers from the internet so they run in offline mode.

.DESCRIPTION
Without arguments the window opens. Command line use:

    LauncherOffline.ps1 status
    LauncherOffline.ps1 offline ubisoft epic [-CloseRunning]
    LauncherOffline.ps1 offline all
    LauncherOffline.ps1 online  all
    LauncherOffline.ps1 sync        # repair rules after a launcher update
    LauncherOffline.ps1 uninstall   # remove every rule and revert settings
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('gui', 'status', 'offline', 'online', 'sync', 'uninstall', 'apply-plan')]
    [string]$Command = 'gui',

    [Parameter(Position = 1, ValueFromRemainingArguments = $true)]
    [string[]]$Launcher = @(),

    # Close running launchers instead of asking the user to restart them.
    [switch]$CloseRunning,

    [ValidateSet('en', 'tr')]
    [string]$Language,

    # Internal: used by the elevated helper process.
    [string]$Plan,
    [string]$ResultFile
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'LauncherOffline.psm1') -Force
if ($Language) { Set-LOLanguage $Language }

function Select-LauncherStatus {
    param([string[]]$Ids, [ValidateSet('Offline', 'Online')][string]$Mode)
    $all = @(Get-LauncherStatus)
    if (-not $Ids.Count) { throw "Name at least one launcher or 'all'. Known: $(($all.Id) -join ', ')" }
    if ($Ids -contains 'all') {
        if ($Mode -eq 'Offline') { return @($all | Where-Object { $_.Installed }) }
        return @($all | Where-Object { $_.Rules.Count })
    }
    foreach ($id in $Ids) {
        $match = $all | Where-Object { $_.Id -eq $id }
        if (-not $match) { throw "Unknown launcher '$id'. Known: $(($all.Id) -join ', ')" }
        if ($Mode -eq 'Offline' -and -not $match.Installed) { throw "$($match.Name) was not found on this PC." }
        $match
    }
}

switch ($Command) {
    'gui' {
        try {
            . (Join-Path $PSScriptRoot 'gui\Gui.ps1')
            Show-LauncherOfflineWindow
        }
        catch {
            # The window runs without a console, so an error would otherwise vanish silently.
            Add-Type -AssemblyName PresentationFramework
            [void][Windows.MessageBox]::Show((Get-LOText 'Error' "$($_.Exception.Message)`n`n$($_.ScriptStackTrace)"),
                (Get-LOText 'AppTitle'), 'OK', 'Error')
            exit 1
        }
    }

    'status' {
        if (-not (Test-FirewallEnabled)) { Write-Warning (Get-LOText 'FirewallOff') }
        Get-LauncherStatus | Select-Object Id, Name, State, Installed,
            @{ n = 'Tested'; e = { $_.Definition.Tested } },
            @{ n = 'Running'; e = { [bool]$_.Running.Count } },
            @{ n = 'Rules'; e = { $_.Rules.Count } } |
            Format-Table -AutoSize
    }

    { $_ -in 'offline', 'online' } {
        $mode   = (Get-Culture).TextInfo.ToTitleCase($Command)
        $status = @(Select-LauncherStatus -Ids $Launcher -Mode $mode)
        $warnings = Set-LauncherMode -Status $status -Mode $mode -CloseRunning:$CloseRunning
        foreach ($s in $status) { Write-Host (Get-LOText "Now$mode" $s.Name) }
        foreach ($w in $warnings) { Write-Warning $w }
    }

    'sync' {
        if (Sync-LauncherRule -IncludeOrphans) { Write-Host 'Rules updated.' } else { Write-Host 'Nothing to repair.' }
    }

    'uninstall' {
        Reset-LauncherOffline
        Write-Host (Get-LOText 'ResetDone')
    }

    'apply-plan' {
        try {
            Invoke-RulePlan -Plan (ConvertFrom-EncodedPlan $Plan)
            if ($ResultFile) { Set-Content -LiteralPath $ResultFile -Value 'OK' -Encoding UTF8 }
            exit 0
        }
        catch {
            if ($ResultFile) {
                Set-Content -LiteralPath $ResultFile -Value "$($_.Exception.Message)`n$($_.ScriptStackTrace)" -Encoding UTF8
            }
            exit 1
        }
    }
}
