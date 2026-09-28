@{
    Id     = 'ubisoft'
    Name   = 'Ubisoft Connect'
    # Tested: with these two blocked the client falls back to offline mode, Far Cry 6
    # runs, and neither the client nor the game opens any outbound connection.
    Tested = $true

    Roots  = @(
        @{ Registry = 'HKLM:\SOFTWARE\WOW6432Node\Ubisoft\Launcher'; Value = 'InstallDir' }
        @{ Scoop = 'ubisoftconnect' }
        @{ Path = '%ProgramFiles(x86)%\Ubisoft\Ubisoft Game Launcher' }
    )
    Block  = @('upc.exe', 'UplayWebCore.exe')
    Close  = @('UbisoftConnect.exe', 'UbisoftGameLauncher.exe', 'UbisoftGameLauncher64.exe')
}
