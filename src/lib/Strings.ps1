# Localization. Each language is one file: locales\<code>.psd1 (see CONTRIBUTING.md).
# English is the reference; missing keys in other languages fall back to it.

# The chosen language is kept in a small JSON file (no registry). It lives in
# %APPDATA%, outside the app folder, so updates do not reset it.
$script:SettingsFile = Join-Path $env:APPDATA 'LauncherOffline\settings.json'

function Get-LOLocale {
    <# Returns @{ <code> = @{ LanguageName; Strings; Launchers } } for every locale file. #>
    param([string]$Path = $script:LocalesDir)
    $locales = @{}
    foreach ($file in Get-ChildItem -Path $Path -Filter '*.psd1') {
        $data = Import-PowerShellDataFile -LiteralPath $file.FullName
        $locales[$file.BaseName] = @{
            LanguageName = $data['LanguageName']
            Strings      = $(if ($data['Strings']) { $data['Strings'] } else { @{} })
            Launchers    = $(if ($data['Launchers']) { $data['Launchers'] } else { @{} })
        }
    }
    $locales
}

$script:LOLocales = Get-LOLocale

function Get-LOAvailableLanguage {
    <# Languages for the picker, English first, then by name. #>
    $script:LOLocales.GetEnumerator() |
        Sort-Object @{ e = { $_.Key -ne 'en' } }, @{ e = { $_.Value.LanguageName } } |
        ForEach-Object { [pscustomobject]@{ Code = $_.Key; Name = $_.Value.LanguageName } }
}

function Get-DefaultLanguage {
    $saved = $null
    if (Test-Path -LiteralPath $script:SettingsFile) {
        try { $saved = (Get-Content -LiteralPath $script:SettingsFile -Raw | ConvertFrom-Json).Language } catch { }
    }
    if ($saved -and $script:LOLocales.ContainsKey($saved)) { return $saved }
    foreach ($culture in (Get-UICulture), (Get-Culture)) {
        foreach ($code in $culture.Name, $culture.TwoLetterISOLanguageName) {
            if ($script:LOLocales.ContainsKey($code)) { return $code }
        }
    }
    'en'
}

$script:LOLanguage = Get-DefaultLanguage

function Set-LOLanguage {
    param([Parameter(Mandatory)][string]$Language, [switch]$Save)
    if (-not $script:LOLocales.ContainsKey($Language)) { return }
    $script:LOLanguage = $Language
    if ($Save) {
        New-Item -ItemType Directory -Path (Split-Path $script:SettingsFile) -Force | Out-Null
        ConvertTo-Json @{ Language = $Language } | Set-Content -LiteralPath $script:SettingsFile -Encoding UTF8
    }
}

function Get-LOLanguage { $script:LOLanguage }

function Get-LOText {
    param([Parameter(Mandatory)][string]$Key, [Parameter(ValueFromRemainingArguments)][object[]]$FormatArgs)
    $text = $script:LOLocales[$script:LOLanguage].Strings[$Key]
    if (-not $text) { $text = $script:LOLocales['en'].Strings[$Key] }
    if (-not $text) { return $Key }
    if ($FormatArgs) { $text -f $FormatArgs } else { $text }
}

function Get-LONote {
    <# The launcher note in the current language. #>
    param([Parameter(Mandatory)][string]$LauncherId)
    $note = $script:LOLocales[$script:LOLanguage].Launchers[$LauncherId]
    if (-not $note) { $note = $script:LOLocales['en'].Launchers[$LauncherId] }
    $note
}
