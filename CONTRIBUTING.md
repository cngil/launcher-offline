# Contributing

## Project layout

```
LauncherOffline.cmd        double-click entry point
install.ps1                one-line installer (irm ... | iex)
assets\                    app icon; New-Icon.ps1 draws it and writes icon.ico
launchers\*.psd1           one data file per supported launcher
locales\*.psd1             one file per language
src\LauncherOffline.ps1    entry script: window + command line
src\LauncherOffline.psm1   core module, loads src\lib\*.ps1
src\lib\                   detection, firewall, actions, localization
src\gui\                   WPF window (XAML + code)
tests\                     Pester 5 tests
```

Everything targets **Windows PowerShell 5.1**, the version built into Windows. Do not use PowerShell 7 only syntax (`??`, `?:`, `&&`, `-Parallel`, ...).

`.ps1`, `.psm1` and `.psd1` files must be saved as **UTF-8 with BOM**. Windows PowerShell reads files without a BOM as ANSI, which garbles non-English text. The one exception is `install.ps1`: it runs through `irm | iex`, where a BOM breaks the script, so it must stay plain ASCII without a BOM. Tests enforce both rules.

## Adding a launcher

Create `launchers\<id>.psd1`:

```powershell
@{
    Id     = 'mylauncher'          # lowercase, must match the file name
    Name   = 'My Launcher'
    Tested = $false                # $true only after the check below

    # Where to look for the install folder, most reliable first.
    Roots  = @(
        @{ Registry = 'HKLM:\SOFTWARE\WOW6432Node\Vendor\Launcher'; Value = 'InstallDir' }
        @{ Scoop = 'my-launcher'; SubPath = 'optional\sub\folder' }
        @{ Path = '%ProgramFiles%\Vendor\Launcher' }
    )

    # Programs (relative to the install folder) that get an outbound block rule.
    # The first one is the main exe and provides the icon. Missing files are skipped.
    Block  = @('Launcher.exe', 'bin\WebHelper.exe')

    # Optional: more programs to close when switching modes.
    Close  = @('Updater.exe')

    # Optional: graceful shutdown command, run before force-closing.
    Shutdown = @{ Exe = 'Launcher.exe'; Arguments = '-shutdown' }
}
```

Add a one-sentence note for users under `Launchers` in `locales\en.psd1` (and in other languages if you can):

```powershell
    Launchers = @{
        mylauncher = 'One thing the user should know about this launcher.'
    }
```

Then check which programs actually talk to the internet. Start the launcher, sign in, and run:

```powershell
Get-NetTCPConnection -State Established |
    Where-Object RemoteAddress -notin '127.0.0.1', '::1' |
    Select-Object RemoteAddress, RemotePort, @{ n = 'Process'; e = { (Get-Process -Id $_.OwningProcess).Path } }
```

Block the fewest programs that make the launcher go offline. Test it: go offline, restart the launcher, start a game, and run the command again. There should be no connection from the launcher. If all of that works, set `Tested = $true` and mark it as tested in the README table.

## Tests

```powershell
Install-Module Pester -MinimumVersion 5.5.0 -Scope CurrentUser -SkipPublisherCheck
Invoke-Pester -Path tests
```

The tests do not touch the real firewall. CI runs them on every push with Windows PowerShell 5.1.

## Adding a language

Every language is a single file in `locales\`, named after its culture code: `de.psd1`, `pt-BR.psd1` and so on. The app finds new files automatically and lists them in the language menu.

1. Copy `locales\en.psd1` to `locales\<code>.psd1`.
2. Set `LanguageName` to the language's own name (`'Deutsch'`, `'Português (Brasil)'`).
3. Translate the values under `Strings` and `Launchers`. Keep the keys and the `{0}` placeholders as they are.
4. Run the tests and open a pull request.

Tips:

- Untranslated keys can be deleted. They fall back to English, so a partial translation is fine.
- Use single quotes. Inside them, write an apostrophe twice: `'Epic''s'`. Strings with line breaks use double quotes and `` `n ``.
- Keep launcher names and button words short. They sit on buttons and status labels.
- The first time the app starts it picks the Windows display language, then the regional format, then English. The choice in the menu is saved to `%APPDATA%\LauncherOffline\settings.json`.

The tests check that every key exists in English, that the placeholders match, and that the file name is a valid culture code.
