@{
    Id     = 'battlenet'
    Name   = 'Battle.net'
    Tested = $false

    # Blizzard supports offline mode for StarCraft: Remastered, StarCraft II,
    # Diablo II: Resurrected and Warcraft III: Reforged after a sign-in within 30 days.
    # https://us.battle.net/support/en/article/000010313
    Roots  = @(
        @{ Scoop = 'battlenet' }
        @{ Path = '%ProgramFiles(x86)%\Battle.net' }
        @{ Path = '%ProgramFiles%\Battle.net' }
    )
    Block  = @('Battle.net.exe', 'Battle.net Launcher.exe')
}
