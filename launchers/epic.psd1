@{
    Id     = 'epic'
    Name   = 'Epic Games Launcher'
    # Tested: blocked, the launcher offers "Continue in Offline Mode" and none of its
    # processes open an outbound connection.
    Tested = $true

    Roots  = @(
        @{ Scoop = 'epic-games-launcher'; SubPath = 'Launcher' }
        @{ Path = '%ProgramFiles(x86)%\Epic Games\Launcher' }
        @{ Path = '%ProgramFiles%\Epic Games\Launcher' }
    )
    Block  = @(
        'Portal\Binaries\Win64\EpicGamesLauncher.exe'
        'Portal\Binaries\Win32\EpicGamesLauncher.exe'
        'Engine\Binaries\Win64\EpicWebHelper.exe'
    )
    Close  = @('Portal\Binaries\Win64\EpicGamesUpdater.exe')
}
