BeforeAll {
    $script:repo = Split-Path $PSScriptRoot -Parent
}

Describe 'Scripts' {
    It '<Name> parses without errors' -ForEach @(
        Get-ChildItem (Split-Path $PSScriptRoot -Parent) -Recurse -Include *.ps1, *.psm1, *.psd1 |
            ForEach-Object { @{ Name = $_.Name; Path = $_.FullName } }
    ) {
        $errors = $null
        [void][Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$errors)
        $errors | Should -BeNullOrEmpty
    }

    # Windows PowerShell 5.1 reads BOM-less files as ANSI, which garbles non-English text.
    It '<Name> is saved as UTF-8 with BOM' -ForEach @(
        Get-ChildItem (Split-Path $PSScriptRoot -Parent) -Recurse -Include *.ps1, *.psm1, *.psd1 |
            Where-Object { $_.Name -ne 'install.ps1' } |
            ForEach-Object { @{ Name = $_.Name; Path = $_.FullName } }
    ) {
        $bytes = [IO.File]::ReadAllBytes($Path)
        ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) | Should -BeTrue
    }

    # install.ps1 runs through `irm | iex`: a BOM would reach iex as a stray character.
    It 'install.ps1 is plain ASCII without BOM' {
        $bytes = [IO.File]::ReadAllBytes((Join-Path $repo 'install.ps1'))
        @($bytes | Where-Object { $_ -gt 127 }).Count | Should -Be 0
    }

    It 'app icon has the sizes Windows asks for' {
        Add-Type -AssemblyName PresentationCore
        $icon = [Windows.Media.Imaging.BitmapDecoder]::Create((New-Object Uri (Join-Path $repo 'assets\icon.ico')), 'None', 'OnLoad')
        $sizes = @($icon.Frames | ForEach-Object { $_.PixelWidth })
        foreach ($size in 16, 32, 48, 256) { $sizes | Should -Contain $size }
    }

    It 'XAML files are valid' {
        Add-Type -AssemblyName PresentationFramework
        foreach ($file in Get-ChildItem (Join-Path $repo 'src\gui') -Filter *.xaml) {
            { [Windows.Markup.XamlReader]::Parse([IO.File]::ReadAllText($file.FullName)) } | Should -Not -Throw
        }
    }
}

Describe 'Locales' {
    BeforeDiscovery {
        $localeFiles = @(Get-ChildItem (Join-Path (Split-Path $PSScriptRoot -Parent) 'locales') -Filter *.psd1 |
                ForEach-Object { @{ Code = $_.BaseName } })
    }

    BeforeAll {
        Import-Module (Join-Path $repo 'src\LauncherOffline.psm1') -Force
        $script:locales  = Get-LOLocale -Path (Join-Path $repo 'locales')
        $script:english  = $locales['en']
        $script:launcherIds = @(Get-LauncherDefinition | ForEach-Object { $_.Id })

        function Get-Placeholder([string]$Text) {
            @([regex]::Matches($Text, '\{\d+\}') | ForEach-Object { $_.Value } | Sort-Object -Unique) -join ','
        }
    }

    It 'English has a note for every launcher' {
        foreach ($id in $launcherIds) { $english.Launchers[$id] | Should -Not -BeNullOrEmpty -Because "launcher '$id'" }
    }

    It 'every text key used in the code exists in English' {
        $code = (Get-ChildItem (Join-Path $repo 'src') -Recurse -Include *.ps1 | Get-Content -Raw) -join "`n"
        $static  = @([regex]::Matches($code, "Get-LOText '(\w+)'") | ForEach-Object { $_.Groups[1].Value })
        $dynamic = foreach ($state in 'Online', 'Offline', 'NeedsRepair') { "State$state"; "Detail$state" }
        $dynamic += 'NowOffline', 'NowOnline'
        foreach ($key in @($static) + @($dynamic) | Sort-Object -Unique) {
            $english.Strings.ContainsKey($key) | Should -BeTrue -Because "key '$key'"
        }
    }

    Context '<Code>' -ForEach $localeFiles {
        BeforeAll { $script:locale = $locales[$Code] }

        It 'file name is a valid culture code' {
            { [Globalization.CultureInfo]::GetCultureInfo($Code) } | Should -Not -Throw
        }

        It 'has a LanguageName' {
            $locale.LanguageName | Should -Not -BeNullOrEmpty
        }

        It 'only uses keys that exist in English' {
            foreach ($key in $locale.Strings.Keys) { $english.Strings.ContainsKey($key) | Should -BeTrue -Because "key '$key'" }
            foreach ($id in $locale.Launchers.Keys) { $launcherIds | Should -Contain $id }
        }

        It 'keeps the same {0} placeholders as English' {
            foreach ($key in $locale.Strings.Keys) {
                Get-Placeholder $locale.Strings[$key] | Should -Be (Get-Placeholder $english.Strings[$key]) -Because "key '$key'"
            }
        }
    }
}
