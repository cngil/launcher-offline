# Windows Firewall access goes through the HNetCfg COM API instead of netsh:
# netsh output is localized, the COM API is not.

function Get-LORule {
    <# Rules created by this tool, identified by their firewall group. #>
    $policy = New-Object -ComObject HNetCfg.FwPolicy2
    foreach ($rule in $policy.Rules) {
        if ($rule.Grouping -eq $script:RuleGroup) {
            [pscustomobject]@{
                Name       = $rule.Name
                LauncherId = Get-RuleLauncherId $rule.Description
                Program    = $rule.ApplicationName
            }
        }
    }
}

function Get-RuleLauncherId {
    # Descriptions look like "LauncherOffline:<id> - ...". The firewall rejects '|' in rule text.
    param([string]$Description)
    if ($Description -match '^LauncherOffline:(\S+)') { $Matches[1] }
}

function Test-FirewallEnabled {
    try {
        $policy  = New-Object -ComObject HNetCfg.FwPolicy2
        $current = $policy.CurrentProfileTypes
        foreach ($type in 1, 2, 4) {
            if (($current -band $type) -and -not $policy.FirewallEnabled($type)) { return $false }
        }
    }
    catch { }
    $true
}

function Test-IsAdmin {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-ShortHash {
    param([string]$Text)
    $sha = [Security.Cryptography.SHA1]::Create()
    $bytes = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text.ToLowerInvariant()))
    ($bytes[0..2] | ForEach-Object { $_.ToString('x2') }) -join ''
}

function Get-RulePlanDiff {
    <#
    .SYNOPSIS
    Plan = @{ launcherId = @(programs that must be blocked) }. An empty list removes
    every rule of that launcher. Launchers missing from the plan are left alone.
    #>
    param([object[]]$Rules = @(), [Parameter(Mandatory)][hashtable]$Plan)

    $add = @(); $remove = @()
    foreach ($id in $Plan.Keys) {
        $desired  = @($Plan[$id] | Where-Object { $_ -is [string] -and $_ } | Sort-Object -Unique)
        $current  = @($Rules | Where-Object { $_.LauncherId -eq $id })
        $existing = @($current | ForEach-Object { $_.Program })

        $remove += @($current | Where-Object { $desired -notcontains $_.Program })
        $add    += @($desired | Where-Object { $existing -notcontains $_ } |
                ForEach-Object { [pscustomobject]@{ LauncherId = $id; Program = $_ } })
    }
    [pscustomobject]@{ Add = $add; Remove = $remove }
}

function Invoke-RulePlan {
    <# Applies a plan to the firewall. Needs administrator rights. #>
    param([Parameter(Mandatory)][hashtable]$Plan)

    $names  = @{}
    Get-LauncherDefinition | ForEach-Object { $names[$_.Id] = $_.Name }
    $policy = New-Object -ComObject HNetCfg.FwPolicy2
    $diff   = Get-RulePlanDiff -Rules @(Get-LORule) -Plan $Plan

    foreach ($rule in $diff.Remove) { $policy.Rules.Remove($rule.Name) }

    foreach ($item in $diff.Add) {
        $display = if ($names[$item.LauncherId]) { $names[$item.LauncherId] } else { $item.LauncherId }
        $rule = New-Object -ComObject HNetCfg.FWRule
        $rule.Name            = "LauncherOffline - $display - $(Split-Path $item.Program -Leaf) ($(Get-ShortHash $item.Program))"
        $rule.Description     = "LauncherOffline:$($item.LauncherId) - managed by Launcher Offline ($script:ProjectUrl)"
        $rule.ApplicationName = $item.Program
        $rule.Grouping        = $script:RuleGroup
        $rule.Direction       = 2            # outbound
        $rule.Action          = 0            # block
        $rule.Profiles        = 0x7FFFFFFF   # all profiles
        $rule.Enabled         = $true
        $policy.Rules.Add($rule)
    }
}

function ConvertTo-EncodedPlan {
    <# Plan -> base64 JSON, safe to pass on a command line. #>
    param([Parameter(Mandatory)][hashtable]$Plan)
    $clean = @{}
    foreach ($id in $Plan.Keys) { $clean[$id] = [string[]]@($Plan[$id] | Where-Object { $_ -is [string] -and $_ }) }
    [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $clean -Compress -Depth 4)))
}

function ConvertFrom-EncodedPlan {
    param([Parameter(Mandatory)][string]$Encoded)
    $json = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Encoded))
    $plan = @{}
    foreach ($p in (ConvertFrom-Json $json).PSObject.Properties) {
        $plan[$p.Name] = @($p.Value | Where-Object { $_ -is [string] -and $_ })
    }
    $plan
}

function Invoke-RulePlanElevated {
    <#
    Runs Invoke-RulePlan with administrator rights. Everything user specific (paths,
    settings files) is resolved by the caller, so this also works when the UAC prompt
    is answered with a different admin account.
    #>
    param([Parameter(Mandatory)][hashtable]$Plan)

    if (Test-IsAdmin) { Invoke-RulePlan -Plan $Plan; return }

    $encoded    = ConvertTo-EncodedPlan -Plan $Plan
    $resultFile = [IO.Path]::GetTempFileName()
    $arguments  = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$script:EntryScript`" apply-plan -Plan $encoded -ResultFile `"$resultFile`""

    try {
        $process = Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -Verb RunAs -WindowStyle Hidden -Wait -PassThru
    }
    catch {
        Remove-Item -LiteralPath $resultFile -ErrorAction SilentlyContinue
        throw 'UAC_CANCELED'
    }

    $result = (Get-Content -LiteralPath $resultFile -Raw -ErrorAction SilentlyContinue)
    Remove-Item -LiteralPath $resultFile -ErrorAction SilentlyContinue
    if ($process.ExitCode -ne 0) {
        if (-not $result) { $result = "exit code $($process.ExitCode)" }
        throw $result.Trim()
    }
}
