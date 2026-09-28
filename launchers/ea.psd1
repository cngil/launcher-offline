@{
    Id     = 'ea'
    Name   = 'EA app'
    Tested = $false

    Roots  = @(
        @{ Registry = 'HKLM:\SOFTWARE\Electronic Arts\EA Desktop'; Value = 'InstallLocation' }
        @{ Path = '%ProgramFiles%\Electronic Arts\EA Desktop\EA Desktop' }
    )
    Block  = @('EADesktop.exe', 'EABackgroundService.exe')
}
