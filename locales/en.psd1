# English is the reference language: every key must exist here.
# Other languages may leave keys out; they fall back to English.
@{
    LanguageName = 'English'

    Strings      = @{
        AppTitle            = 'Launcher Offline'
        Subtitle            = 'Cuts game launchers off the internet so they start in offline mode. No more session kicks or password prompts.'
        StateOnline         = 'Online'
        StateOffline        = 'Offline'
        StateNeedsRepair    = 'Needs repair'
        GoOffline           = 'Go offline'
        GoOnline            = 'Go online'
        Repair              = 'Repair'
        Running             = 'Running'
        DetailOffline       = 'Internet access blocked.'
        DetailOnline        = 'Connects to the internet normally.'
        DetailNeedsRepair   = 'The launcher was updated or moved. Repair to block it again.'
        AskCloseTitle       = '{0} is running'
        AskClose            = 'It has to be closed for the change to take effect. If a game is open, save and quit it first.'
        CloseAndContinue    = 'Close and continue'
        KeepOpen            = 'Keep it open'
        Cancel              = 'Cancel'
        NowOffline          = '{0} is now offline. Open it and play.'
        NowOnline           = '{0} can connect to the internet again.'
        Repaired            = 'The block for {0} was refreshed.'
        RestartLauncher     = 'Restart {0} for the change to take effect.'
        UacCanceled         = 'Permission was not granted. Nothing was changed.'
        Error               = 'Something went wrong: {0}'
        FirewallOff         = 'Windows Firewall is turned off, so blocking will not work. Turn it on in Windows Security.'
        NoneFound           = 'No supported launcher was found on this PC.'
        NotFound            = 'Supported, not found on this PC: {0}'
        Refresh             = 'Refresh'
        ResetAll            = 'Remove all blocks'
        ConfirmResetTitle   = 'Remove all blocks?'
        ConfirmReset        = 'Every launcher goes back online. You can take them offline again at any time.'
        ResetDone           = 'All blocks were removed.'
        Footer              = 'Each change asks for administrator permission once.'
    }

    # One note per launcher id (see launchers\*.psd1), shown under its name.
    Launchers    = @{
        ubisoft  = 'Sharing one account on two PCs? Turn off cloud save sync (Settings > General) so saves do not overwrite each other.'
        epic     = 'When it starts, press "Continue in Offline Mode". You must have signed in before. Games using Epic Online Services may still need internet.'
        rockstar = 'Story modes work offline after one online sign-in. Online modes (GTA Online, Red Dead Online) need internet.'
        ea       = 'Sign in online at least once before going offline.'
        battlenet = 'Offline mode works for StarCraft: Remastered, StarCraft II, Diablo II: Resurrected and Warcraft III: Reforged if you signed in within the last 30 days.'
    }
}
