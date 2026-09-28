function Stop-Launcher {
    <# Closes a launcher: graceful shutdown command if the definition has one, then kill what is left. #>
    param([Parameter(Mandatory)]$Status, [int]$TimeoutSeconds = 15)

    $ids = @($Status.Running | ForEach-Object { $_.Id })
    if (-not $ids.Count) { return }

    $shutdown = $Status.Definition.Shutdown
    if ($shutdown) {
        $exe = Join-Path $Status.Root $shutdown.Exe
        if (Test-Path -LiteralPath $exe) {
            Start-Process -FilePath $exe -ArgumentList $shutdown.Arguments -ErrorAction SilentlyContinue
            Wait-ProcessExit -Id $ids -TimeoutSeconds $TimeoutSeconds
        }
    }

    Get-Process -Id $ids -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Wait-ProcessExit -Id $ids -TimeoutSeconds 5
}

function Wait-ProcessExit {
    param([int[]]$Id, [int]$TimeoutSeconds)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Process -Id $Id -ErrorAction SilentlyContinue) -and (Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 250
    }
}

function Set-LauncherMode {
    <#
    .SYNOPSIS
    Takes launchers offline (block rules) or back online. Returns warnings
    for the user, e.g. when a launcher kept running and must be restarted.
    #>
    param(
        [Parameter(Mandatory)][object[]]$Status,
        [Parameter(Mandatory)][ValidateSet('Offline', 'Online')][string]$Mode,
        [switch]$CloseRunning
    )

    $warnings = New-Object System.Collections.Generic.List[string]
    $plan     = @{}
    $running  = @{}

    foreach ($s in $Status) {
        if ($Mode -eq 'Offline' -and -not $s.Installed) { continue }
        $running[$s.Id] = $s.Running.Count -gt 0
        if ($running[$s.Id] -and $CloseRunning) {
            Stop-Launcher -Status $s
            $running[$s.Id] = $false
        }
        # Assign directly: `$x = if (...) { @() }` would store $null, not an empty list.
        if ($Mode -eq 'Offline') { $plan[$s.Id] = @($s.Exes) } else { $plan[$s.Id] = @() }
    }
    if (-not $plan.Count) { return $warnings }

    Invoke-RulePlanElevated -Plan $plan

    foreach ($s in $Status | Where-Object { $plan.ContainsKey($_.Id) }) {
        if ($running[$s.Id]) { $warnings.Add((Get-LOText 'RestartLauncher' $s.Name)) }
    }
    $warnings
}

function Sync-LauncherRule {
    <#
    .SYNOPSIS
    Re-points block rules after a launcher was updated or moved and removes rules of
    launchers that no longer exist. Returns $true if anything had to change.
    #>
    param([object[]]$Status = @(Get-LauncherStatus), [switch]$IncludeOrphans)

    $plan = @{}
    foreach ($s in $Status | Where-Object { $_.State -eq 'NeedsRepair' }) {
        $plan[$s.Id] = @(Get-DesiredProgram $s)
    }
    if ($IncludeOrphans) {
        $known = @(Get-LauncherDefinition | ForEach-Object { $_.Id })
        foreach ($id in @(Get-LORule | ForEach-Object { $_.LauncherId } | Sort-Object -Unique)) {
            if ($known -notcontains $id) { $plan[$id] = @() }
        }
    }
    if (-not $plan.Count) { return $false }
    Invoke-RulePlanElevated -Plan $plan
    $true
}

function Reset-LauncherOffline {
    <# Removes every rule this tool created: the uninstall step. #>
    $plan = @{}
    foreach ($id in @(Get-LORule | ForEach-Object { $_.LauncherId } | Sort-Object -Unique)) { $plan[$id] = @() }
    if ($plan.Count) { Invoke-RulePlanElevated -Plan $plan }
}
