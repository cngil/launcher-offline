# WPF window. Dot-sourced by LauncherOffline.ps1; all logic lives in the module.
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Drawing

$script:IconPath = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'assets\icon.ico'

$script:Palette = @{
    Offline     = @{ Back = '#DCFCE7'; Fore = '#166534' }
    Online      = @{ Back = '#F3F4F6'; Fore = '#374151' }
    NeedsRepair = @{ Back = '#FEF3C7'; Fore = '#92400E' }
    ok          = @{ Back = '#ECFDF5'; Border = '#A7F3D0'; Fore = '#065F46' }
    warn        = @{ Back = '#FFFBEB'; Border = '#FDE68A'; Fore = '#92400E' }
    error       = @{ Back = '#FEF2F2'; Border = '#FECACA'; Fore = '#991B1B' }
}

function ConvertTo-Brush([string]$Hex) {
    (New-Object Windows.Media.BrushConverter).ConvertFromString($Hex)
}

function Import-Xaml([string]$Name) {
    [Windows.Markup.XamlReader]::Parse([IO.File]::ReadAllText((Join-Path $PSScriptRoot $Name)))
}

function Get-ExeIcon([string]$Path) {
    try {
        $icon   = [Drawing.Icon]::ExtractAssociatedIcon($Path)
        $source = [Windows.Interop.Imaging]::CreateBitmapSourceFromHIcon(
            $icon.Handle, [Windows.Int32Rect]::Empty, [Windows.Media.Imaging.BitmapSizeOptions]::FromEmptyOptions())
        $source.Freeze()
        $source
    }
    catch { $null }
}

function Show-Banner([string]$Text, [string]$Kind = 'ok') {
    $colors = $script:Palette[$Kind]
    $script:UI.Banner.Background  = ConvertTo-Brush $colors.Back
    $script:UI.Banner.BorderBrush = ConvertTo-Brush $colors.Border
    $script:UI.BannerText.Foreground = ConvertTo-Brush $colors.Fore
    $script:UI.BannerText.Text = $Text
    $script:UI.Banner.Visibility = 'Visible'
}

function Set-Busy([bool]$Busy) {
    $script:Window.Cursor = if ($Busy) { [Windows.Input.Cursors]::Wait } else { $null }
    $script:UI.Cards.IsEnabled = -not $Busy
    $script:UI.RefreshButton.IsEnabled = -not $Busy
    $script:UI.ResetButton.IsEnabled = -not $Busy
    # Let WPF paint the disabled state before the (blocking) work starts.
    $script:Window.Dispatcher.Invoke([Action] {}, [Windows.Threading.DispatcherPriority]::Background)
}

function New-LauncherCard($Status) {
    $card = Import-Xaml 'Card.xaml'
    $find = { param($n) $card.FindName($n) }

    # The first Block entry is the main launcher exe, so it has the right icon.
    $main = if ($Status.Installed) { Join-Path $Status.Root $Status.Definition.Block[0] }
    $exe = @(@($main) + $Status.Exes + @($Status.Rules | ForEach-Object { $_.Program })) |
        Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
    if ($exe) { (& $find 'IconImage').Source = Get-ExeIcon $exe }

    (& $find 'NameText').Text = $Status.Name
    $colors = $script:Palette[$Status.State]
    $pill = & $find 'Pill'
    $pill.Background = ConvertTo-Brush $colors.Back
    (& $find 'PillText').Foreground = ConvertTo-Brush $colors.Fore
    (& $find 'PillText').Text = Get-LOText "State$($Status.State)"

    if ($Status.Running.Count) {
        (& $find 'RunningPill').Visibility = 'Visible'
        (& $find 'RunningText').Text = Get-LOText 'Running'
    }

    (& $find 'DetailText').Text = Get-LOText "Detail$($Status.State)"
    (& $find 'DetailText').ToolTip = (@($Status.Exes) + @($Status.Rules | ForEach-Object { $_.Program }) | Sort-Object -Unique) -join "`n"
    $note = Get-LONote $Status.Id
    if ($note) { (& $find 'NoteText').Text = $note } else { (& $find 'NoteText').Visibility = 'Collapsed' }

    $button = & $find 'ActionButton'
    $button.Tag = $Status.Id
    switch ($Status.State) {
        'Online' {
            $button.Content = Get-LOText 'GoOffline'
            $button.Add_Click({ param($sender) Invoke-CardAction -Id $sender.Tag -Action Offline })
        }
        'Offline' {
            $button.Content = Get-LOText 'GoOnline'
            $button.Background = ConvertTo-Brush '#FFFFFF'
            $button.Foreground = ConvertTo-Brush '#111827'
            $button.BorderBrush = ConvertTo-Brush '#D1D5DB'
            $button.Add_Click({ param($sender) Invoke-CardAction -Id $sender.Tag -Action Online })
        }
        'NeedsRepair' {
            $button.Content = Get-LOText 'Repair'
            $button.Background = ConvertTo-Brush '#D97706'
            $button.Add_Click({ param($sender) Invoke-CardAction -Id $sender.Tag -Action Repair })
        }
    }
    $card
}

function Update-View {
    $all = @(Get-LauncherStatus)
    # Launchers that are blocked or need attention first, then by name.
    $order = @{ NeedsRepair = 0; Offline = 1; Online = 2 }
    $visible = @($all | Where-Object { $_.Installed -or $_.Rules.Count } | Sort-Object { $order[$_.State] }, Name)
    $missing = @($all | Where-Object { -not ($_.Installed -or $_.Rules.Count) } | ForEach-Object { $_.Name })

    $script:UI.Cards.Children.Clear()
    foreach ($s in $visible) { [void]$script:UI.Cards.Children.Add((New-LauncherCard $s)) }
    if (-not $visible.Count) {
        $empty = New-Object Windows.Controls.TextBlock
        $empty.Text = Get-LOText 'NoneFound'
        $empty.Foreground = ConvertTo-Brush '#6B7280'
        $empty.Margin = '0,12,0,12'
        [void]$script:UI.Cards.Children.Add($empty)
    }
    $script:UI.MissingText.Text = if ($missing.Count) { Get-LOText 'NotFound' ($missing -join ', ') } else { '' }
    $script:UI.ResetButton.Visibility = if (@($all | Where-Object { $_.Rules.Count }).Count) { 'Visible' } else { 'Collapsed' }
}

function Invoke-Safely([scriptblock]$Work) {
    Set-Busy $true
    try { & $Work }
    catch {
        # Errors from the elevated helper carry a stack trace after the first line.
        $message = @($_.Exception.Message -split "`r?`n")[0]
        if ($message -eq 'UAC_CANCELED') { Show-Banner (Get-LOText 'UacCanceled') 'warn' }
        else { Show-Banner (Get-LOText 'Error' $message) 'error' }
    }
    finally {
        try { Update-View } catch { Show-Banner (Get-LOText 'Error' $_.Exception.Message) 'error' }
        Set-Busy $false
    }
}

function Show-Dialog {
    <#
    .SYNOPSIS
    Modal dialog drawn inside the window in the app's own style. Blocks like a
    message box (nested dispatcher frame) and returns the Result of the clicked button.
    Buttons: @{ Text; Result; Kind = 'primary' | 'danger' | (secondary); Default; Cancel }
    Enter clicks the Default button, Esc answers with the Cancel button's Result.
    #>
    param([string]$Title, [string]$Message, [object[]]$Buttons)

    $script:UI.DialogTitle.Text = $Title
    $script:UI.DialogText.Text = $Message
    $script:UI.DialogButtons.Children.Clear()
    $script:DialogResult = $null
    $script:DialogCancelResult = $null
    $focus = $null

    foreach ($spec in $Buttons) {
        $button = New-Object Windows.Controls.Button
        $button.Content = $spec.Text
        $button.Tag = $spec.Result
        $button.Margin = '8,0,0,0'
        $button.MinWidth = 96
        switch ($spec['Kind']) {
            'primary' { }
            'danger' { $button.Background = ConvertTo-Brush '#DC2626' }
            default {
                $button.Background = ConvertTo-Brush '#FFFFFF'
                $button.Foreground = ConvertTo-Brush '#111827'
                $button.BorderBrush = ConvertTo-Brush '#D1D5DB'
            }
        }
        if ($spec['Default']) { $button.IsDefault = $true; $focus = $button }
        # Not Button.IsCancel: in a window opened with ShowDialog it closes the whole window.
        # Esc is handled in the window's PreviewKeyDown instead.
        if ($spec['Cancel']) { $script:DialogCancelResult = $spec.Result }
        $button.Add_Click({
                param($sender)
                $script:DialogResult = $sender.Tag
                if ($script:DialogFrame) { $script:DialogFrame.Continue = $false }
            })
        [void]$script:UI.DialogButtons.Children.Add($button)
    }

    $script:UI.DialogLayer.Visibility = 'Visible'
    $script:Window.UpdateLayout()
    if ($focus) { [void]$focus.Focus() }

    $script:DialogFrame = New-Object Windows.Threading.DispatcherFrame
    [Windows.Threading.Dispatcher]::PushFrame($script:DialogFrame)
    $script:DialogFrame = $null
    $script:UI.DialogLayer.Visibility = 'Collapsed'
    $script:DialogResult
}

function Invoke-CardAction([string]$Id, [string]$Action) {
    $status = @(Get-LauncherStatus) | Where-Object { $_.Id -eq $Id }
    if (-not $status) { return }

    $close = $false
    if ($Action -ne 'Repair' -and $status.Running.Count) {
        $answer = Show-Dialog -Title (Get-LOText 'AskCloseTitle' $status.Name) -Message (Get-LOText 'AskClose') -Buttons @(
            @{ Text = (Get-LOText 'Cancel'); Result = 'Cancel'; Cancel = $true }
            @{ Text = (Get-LOText 'KeepOpen'); Result = 'Keep' }
            @{ Text = (Get-LOText 'CloseAndContinue'); Result = 'Close'; Kind = 'primary'; Default = $true }
        )
        if ($answer -eq 'Cancel') { return }
        $close = $answer -eq 'Close'
    }

    Invoke-Safely {
        if ($Action -eq 'Repair') {
            [void](Sync-LauncherRule -Status @($status))
            Show-Banner (Get-LOText 'Repaired' $status.Name) 'ok'
            return
        }
        $warnings = @(Set-LauncherMode -Status @($status) -Mode $Action -CloseRunning:$close)
        $lines = @(Get-LOText "Now$Action" $status.Name) + $warnings
        Show-Banner ($lines -join "`n") $(if ($warnings.Count) { 'warn' } else { 'ok' })
    }
}

function Set-WindowText {
    $script:Window.Title = Get-LOText 'AppTitle'
    $script:UI.TitleText.Text = Get-LOText 'AppTitle'
    $script:UI.SubtitleText.Text = Get-LOText 'Subtitle'
    $script:UI.FooterText.Text = Get-LOText 'Footer'
    $script:UI.RefreshButton.Content = Get-LOText 'Refresh'
    $script:UI.ResetButton.Content = Get-LOText 'ResetAll'
}

function Show-LauncherOfflineWindow {
    $script:Window = Import-Xaml 'MainWindow.xaml'
    $script:UI = @{}
    foreach ($name in 'TitleText', 'SubtitleText', 'LanguageBox', 'Banner', 'BannerText', 'Cards', 'MissingText', 'FooterText',
        'RepoLink', 'RepoLinkText', 'RefreshButton', 'ResetButton', 'DialogLayer', 'DialogTitle', 'DialogText', 'DialogButtons') {
        $script:UI[$name] = $script:Window.FindName($name)
    }
    $script:Window.MaxHeight = [Math]::Max(480, [Windows.SystemParameters]::WorkArea.Height - 40)

    # App icon for the title bar, the taskbar and the header.
    if (Test-Path -LiteralPath $script:IconPath) {
        $icon = [Windows.Media.Imaging.BitmapDecoder]::Create((New-Object Uri $script:IconPath), 'None', 'OnLoad')
        $script:Window.Icon = $icon.Frames | Sort-Object PixelWidth | Select-Object -Last 1
        $script:Window.FindName('AppIcon').Source = $icon.Frames | Where-Object { $_.PixelWidth -eq 128 } | Select-Object -First 1
    }
    Set-WindowText

    # Link to the project page (source, issues, updates) in the footer.
    $script:UI.RepoLink.NavigateUri = New-Object Uri (Get-LOProjectUrl)
    $script:UI.RepoLinkText.Text = (Get-LOProjectUrl) -replace '^https://', ''
    $script:UI.RepoLink.Add_RequestNavigate({
            param($sender, $e)
            Start-Process $e.Uri.AbsoluteUri
            $e.Handled = $true
        })

    # Every locales\*.psd1 file shows up here automatically.
    $languages = @(Get-LOAvailableLanguage)
    $script:UI.LanguageBox.ItemsSource = $languages
    $script:UI.LanguageBox.SelectedItem = $languages | Where-Object { $_.Code -eq (Get-LOLanguage) } | Select-Object -First 1
    $script:UI.LanguageBox.Add_SelectionChanged({
            $choice = $script:UI.LanguageBox.SelectedItem
            if (-not $choice -or $choice.Code -eq (Get-LOLanguage)) { return }
            Set-LOLanguage $choice.Code -Save
            $script:UI.Banner.Visibility = 'Collapsed'
            Set-WindowText
            Update-View
        })

    $script:UI.RefreshButton.Add_Click({
            $script:UI.Banner.Visibility = 'Collapsed'
            Invoke-Safely { }
        })
    $script:UI.ResetButton.Add_Click({
            $answer = Show-Dialog -Title (Get-LOText 'ConfirmResetTitle') -Message (Get-LOText 'ConfirmReset') -Buttons @(
                @{ Text = (Get-LOText 'Cancel'); Result = 'Cancel'; Cancel = $true; Default = $true }
                @{ Text = (Get-LOText 'ResetAll'); Result = 'Reset'; Kind = 'danger' }
            )
            if ($answer -ne 'Reset') { return }
            Invoke-Safely {
                Reset-LauncherOffline
                Show-Banner (Get-LOText 'ResetDone') 'ok'
            }
        })

    # Closing the window while a dialog is open must release the dialog's nested frame.
    $script:Window.Add_Closing({ if ($script:DialogFrame) { $script:DialogFrame.Continue = $false } })

    # Esc answers an open dialog with its Cancel button.
    $script:Window.Add_PreviewKeyDown({
            param($sender, $e)
            if ($script:DialogFrame -and $e.Key -eq [Windows.Input.Key]::Escape -and $script:DialogCancelResult) {
                $script:DialogResult = $script:DialogCancelResult
                $script:DialogFrame.Continue = $false
                $e.Handled = $true
            }
        })

    $script:Window.Add_ContentRendered({
            if (-not (Test-FirewallEnabled)) { Show-Banner (Get-LOText 'FirewallOff') 'error' }
        })

    Update-View
    [void]$script:Window.ShowDialog()
}
