BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\src\LauncherOffline.psm1') -Force

    function New-TestRule($Id, $Program) {
        [pscustomobject]@{ Name = "rule-$Program"; LauncherId = $Id; Program = $Program }
    }
}

Describe 'Get-RulePlanDiff' {
    It 'adds rules for new programs' {
        $diff = Get-RulePlanDiff -Rules @() -Plan @{ ubisoft = @('C:\a\upc.exe', 'C:\a\web.exe') }
        $diff.Add.Program | Should -Be @('C:\a\upc.exe', 'C:\a\web.exe')
        $diff.Remove | Should -BeNullOrEmpty
    }

    It 'replaces rules that point to an old version folder' {
        $rules = @(New-TestRule ubisoft 'C:\v1\upc.exe')
        $diff  = Get-RulePlanDiff -Rules $rules -Plan @{ ubisoft = @('C:\v2\upc.exe') }
        $diff.Remove.Program | Should -Be 'C:\v1\upc.exe'
        $diff.Add.Program | Should -Be 'C:\v2\upc.exe'
    }

    It 'does nothing when rules already match, ignoring case' {
        $rules = @(New-TestRule ubisoft 'C:\A\UPC.exe')
        $diff  = Get-RulePlanDiff -Rules $rules -Plan @{ ubisoft = @('c:\a\upc.exe') }
        $diff.Add | Should -BeNullOrEmpty
        $diff.Remove | Should -BeNullOrEmpty
    }

    It 'removes all rules of a launcher for an empty list' {
        $rules = @((New-TestRule epic 'C:\e\epic.exe'), (New-TestRule epic 'C:\e\web.exe'))
        $diff  = Get-RulePlanDiff -Rules $rules -Plan @{ epic = @() }
        $diff.Remove.Count | Should -Be 2
        $diff.Add | Should -BeNullOrEmpty
    }

    It 'leaves launchers that are not in the plan alone' {
        $rules = @((New-TestRule epic 'C:\e\epic.exe'), (New-TestRule ubisoft 'C:\u\upc.exe'))
        $diff  = Get-RulePlanDiff -Rules $rules -Plan @{ ubisoft = @() }
        $diff.Remove.LauncherId | Should -Be 'ubisoft'
    }
}

Describe 'Encoded plan' {
    It 'round-trips programs' {
        $plan = ConvertFrom-EncodedPlan (ConvertTo-EncodedPlan @{ ubisoft = @('C:\a\upc.exe', 'C:\a\web.exe') })
        $plan.ubisoft | Should -Be @('C:\a\upc.exe', 'C:\a\web.exe')
    }

    It 'keeps an empty list empty when going online (<Name>)' -ForEach @(
        @{ Name = 'empty array'; Value = @() }
        @{ Name = 'null'; Value = $null }
    ) {
        $plan = ConvertFrom-EncodedPlan (ConvertTo-EncodedPlan @{ epic = $Value })
        $plan.ContainsKey('epic') | Should -BeTrue
        @($plan.epic).Count | Should -Be 0
        $rules = @([pscustomobject]@{ Name = 'r'; LauncherId = 'epic'; Program = 'C:\e.exe' })
        $diff = Get-RulePlanDiff -Rules $rules -Plan $plan
        $diff.Add | Should -BeNullOrEmpty
        $diff.Remove.Count | Should -Be 1
    }

    It 'keeps a single program as a list' {
        $plan = ConvertFrom-EncodedPlan (ConvertTo-EncodedPlan @{ ea = 'C:\ea.exe' })
        @($plan.ea) | Should -Be @('C:\ea.exe')
    }
}

Describe 'Get-RuleLauncherId' {
    It 'reads the id from our description format' {
        Get-RuleLauncherId 'LauncherOffline:ubisoft - managed by Launcher Offline' | Should -Be 'ubisoft'
    }
    It 'ignores foreign rules' {
        Get-RuleLauncherId 'Some other rule' | Should -BeNullOrEmpty
    }
}

Describe 'Get-ShortHash' {
    It 'is stable and case-insensitive' {
        Get-ShortHash 'C:\A\upc.exe' | Should -Be (Get-ShortHash 'c:\a\UPC.EXE')
        Get-ShortHash 'C:\A\upc.exe' | Should -Match '^[0-9a-f]{6}$'
    }
}
