BeforeDiscovery {
    Import-Module (Join-Path $PSScriptRoot '..\src\LauncherOffline.psm1') -Force
}

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\src\LauncherOffline.psm1') -Force

    function New-FakeFile([string]$Path) {
        New-Item -ItemType File -Path $Path -Force | Out-Null
    }
}

Describe 'Launcher definitions' {
    BeforeAll {
        $script:defs = @(Get-LauncherDefinition)
    }

    It 'loads at least one definition' {
        $defs.Count | Should -BeGreaterThan 0
    }

    It '<File> has the required fields' -ForEach @(Get-LauncherDefinition | ForEach-Object { @{ File = $_.File; Def = $_ } }) {
        $Def.Id | Should -Match '^[a-z0-9-]+$'
        $Def.Name | Should -Not -BeNullOrEmpty
        $Def.Roots.Count | Should -BeGreaterThan 0
        $Def.Block.Count | Should -BeGreaterThan 0
        $Def.File | Should -Be "$($Def.Id).psd1"
        foreach ($root in $Def.Roots) {
            @('Registry', 'Scoop', 'Path' | Where-Object { $root.ContainsKey($_) }).Count | Should -Be 1
            if ($root.ContainsKey('Registry')) { $root.Value | Should -Not -BeNullOrEmpty }
        }
    }

    It 'has unique ids' {
        ($defs.Id | Sort-Object -Unique).Count | Should -Be $defs.Count
    }
}

Describe 'Resolve-RealPath' {
    It 'follows a junction in the middle of a path' {
        $real = Join-Path $TestDrive 'v1.2.3'
        New-FakeFile (Join-Path $real 'app.exe')
        New-Item -ItemType Junction -Path (Join-Path $TestDrive 'current') -Target $real | Out-Null

        Resolve-RealPath (Join-Path $TestDrive 'current\app.exe') | Should -Be (Join-Path $real 'app.exe')
    }

    It 'returns normal paths unchanged' {
        $file = Join-Path $TestDrive 'plain\app.exe'
        New-FakeFile $file
        Resolve-RealPath $file | Should -Be $file
    }
}

Describe 'Find-Launcher' {
    BeforeAll {
        $script:root = Join-Path $TestDrive 'FakeLauncher'
        New-FakeFile (Join-Path $root 'client.exe')
        New-FakeFile (Join-Path $root 'bin\helper.exe')
        New-FakeFile (Join-Path $TestDrive 'Shared\social.exe')

        $script:def = [pscustomobject]@{
            Id = 'fake'; Name = 'Fake'
            Roots = @(@{ Path = (Join-Path $TestDrive 'missing') }, @{ Path = $root })
            Block = @('client.exe', 'bin\helper.exe', 'notinstalled.exe', '..\Shared\social.exe')
            Close = @()
        }
    }

    It 'skips missing folders and finds existing executables' {
        $found = Find-Launcher -Definition $def
        $found.Root | Should -Be $root
        $found.Exes.Count | Should -Be 3
        $found.Exes | Should -Contain (Join-Path $root 'bin\helper.exe')
        $found.Exes | Should -Contain (Join-Path $TestDrive 'Shared\social.exe')
    }

    It 'returns nothing when the launcher is not installed' {
        $missing = $def.PSObject.Copy()
        $missing.Roots = @(@{ Path = (Join-Path $TestDrive 'nope') })
        Find-Launcher -Definition $missing | Should -BeNullOrEmpty
    }

    It 'can locate the folder from a running process' {
        $fromProcess = $def.PSObject.Copy()
        $fromProcess.Roots = @(@{ Path = (Join-Path $TestDrive 'nope') })
        $found = Find-Launcher -Definition $fromProcess -ProcessPath @(Join-Path $root 'bin\helper.exe')
        $found.Root | Should -Be $root
    }
}

Describe 'Get-LauncherStatus' {
    BeforeAll {
        $script:root = Join-Path $TestDrive 'StatusLauncher'
        New-FakeFile (Join-Path $root 'client.exe')
        $script:exe = Join-Path $root 'client.exe'
        $script:def = [pscustomobject]@{
            Id = 'fake'; Name = 'Fake'; Tested = $true; Roots = @(@{ Path = $root })
            Block = @('client.exe'); Close = @(); Shutdown = $null
        }
    }

    It 'is Online without rules' {
        $s = Get-LauncherStatus -Definitions @($def) -Rules @() -Processes @()
        $s.State | Should -Be 'Online'
        $s.Installed | Should -BeTrue
    }

    It 'is Offline when rules match the installed files' {
        $rules = @([pscustomobject]@{ Name = 'r'; LauncherId = 'fake'; Program = $exe })
        (Get-LauncherStatus -Definitions @($def) -Rules $rules -Processes @()).State | Should -Be 'Offline'
    }

    It 'needs repair when rules point to an old location' {
        $rules = @([pscustomobject]@{ Name = 'r'; LauncherId = 'fake'; Program = 'C:\old\client.exe' })
        (Get-LauncherStatus -Definitions @($def) -Rules $rules -Processes @()).State | Should -Be 'NeedsRepair'
    }

    It 'detects a running launcher' {
        $procs = @([pscustomobject]@{ Id = 1; Name = 'client.exe'; Path = $exe })
        (Get-LauncherStatus -Definitions @($def) -Rules @() -Processes $procs).Running.Count | Should -Be 1
    }

    It 'ignores an unrelated process with the same name' {
        $procs = @([pscustomobject]@{ Id = 1; Name = 'client.exe'; Path = 'C:\Other\client.exe' })
        (Get-LauncherStatus -Definitions @($def) -Rules @() -Processes $procs).Running.Count | Should -Be 0
    }
}
