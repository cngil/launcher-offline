@{
    Id     = 'rockstar'
    Name   = 'Rockstar Games Launcher'
    # The block holds (offline banner, no outbound connection) but the offline library
    # has not been checked with a signed-in account yet.
    Tested = $false

    Roots  = @(
        @{ Registry = 'HKLM:\SOFTWARE\WOW6432Node\Rockstar Games\Launcher'; Value = 'InstallFolder' }
        @{ Path = '%ProgramFiles%\Rockstar Games\Launcher' }
    )
    # LauncherPatcher.exe was seen connecting while the launcher was otherwise blocked.
    Block  = @(
        'Launcher.exe'
        'LauncherPatcher.exe'
        'RockstarService.exe'
        '..\Social Club\SocialClubHelper.exe'
    )
}
