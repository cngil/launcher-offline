function Get-LauncherDefinition {
    <# Loads every launchers\*.psd1 file. Adding a launcher = adding one of these files. #>
    param([string]$Path = $script:LaunchersDir)

    foreach ($file in Get-ChildItem -Path $Path -Filter '*.psd1' | Sort-Object Name) {
        $d = Import-PowerShellDataFile -LiteralPath $file.FullName
        [pscustomobject]@{
            Id       = $d.Id
            Name     = $d.Name
            Tested   = [bool]$d['Tested']
            Roots    = @($d['Roots'])
            Block    = @($d['Block'])
            Close    = @($d['Close'] | Where-Object { $_ })
            Shutdown = $d['Shutdown']
            File     = $file.Name
        }
    }
}

function Get-LauncherRootCandidate {
    <# Yields possible install folders, most trustworthy first. #>
    param([Parameter(Mandatory)]$Definition, [string[]]$ProcessPath = @())

    foreach ($source in $Definition.Roots) {
        $dirs = @()
        if ($source['Registry']) {
            $item = Get-ItemProperty -LiteralPath $source.Registry -ErrorAction SilentlyContinue
            if ($item -and $item.PSObject.Properties[$source.Value]) {
                $value = ([string]$item.($source.Value)).Trim().Trim('"')
                if ($value) {
                    if (Test-Path -LiteralPath $value -PathType Leaf) { $value = Split-Path $value -Parent }
                    $dirs += $value
                }
            }
        }
        elseif ($source['Scoop']) {
            foreach ($scoopRoot in Get-ScoopRoot) {
                $dirs += Join-Path $scoopRoot "apps\$($source.Scoop)\current"
            }
        }
        elseif ($source['Path']) {
            $dirs += [Environment]::ExpandEnvironmentVariables($source.Path)
        }

        foreach ($dir in $dirs) {
            if ($source['SubPath']) { Join-Path $dir $source.SubPath } else { $dir }
        }
    }

    # Last resort: derive the folder from a running process. Kept last because
    # generic names like Launcher.exe could belong to an unrelated program.
    foreach ($path in $ProcessPath) {
        foreach ($relative in $Definition.Block) {
            if ($relative.StartsWith('..')) { continue }
            $suffix = '\' + $relative
            if ($path.EndsWith($suffix, [StringComparison]::OrdinalIgnoreCase)) {
                $path.Substring(0, $path.Length - $suffix.Length)
            }
        }
    }
}

function Resolve-LauncherFile {
    param([Parameter(Mandatory)][string]$Root, [string[]]$Relative)
    $files = foreach ($rel in $Relative) {
        $file = [IO.Path]::GetFullPath((Join-Path $Root $rel))
        if (Test-Path -LiteralPath $file -PathType Leaf) { Resolve-RealPath $file }
    }
    @($files | Sort-Object -Unique)
}

function Find-Launcher {
    <# Returns @{ Root; Exes; CloseExes } for the first candidate folder that contains the launcher, or $null. #>
    param([Parameter(Mandatory)]$Definition, [string[]]$ProcessPath = @())

    foreach ($root in Get-LauncherRootCandidate -Definition $Definition -ProcessPath $ProcessPath) {
        if (-not $root -or -not (Test-Path -LiteralPath $root -PathType Container)) { continue }
        $exes = @(Resolve-LauncherFile -Root $root -Relative $Definition.Block)
        if ($exes.Count) {
            return [pscustomobject]@{
                Root      = Resolve-RealPath $root
                Exes      = $exes
                CloseExes = @(Resolve-LauncherFile -Root $root -Relative $Definition.Close)
            }
        }
    }
    $null
}

function Get-ProcessSnapshot {
    Get-CimInstance -ClassName Win32_Process -Property ProcessId, Name, ExecutablePath -ErrorAction SilentlyContinue |
        Where-Object { $_.ExecutablePath } |
        ForEach-Object { [pscustomobject]@{ Id = $_.ProcessId; Name = $_.Name; Path = $_.ExecutablePath } }
}

function Get-LauncherStatus {
    <#
    .SYNOPSIS
    One object per supported launcher: where it is installed, whether it is running,
    which block rules exist and the resulting State (Online / Offline / NeedsRepair).
    #>
    param(
        [object[]]$Definitions = @(Get-LauncherDefinition),
        [object[]]$Rules = @(Get-LORule),
        [object[]]$Processes = @(Get-ProcessSnapshot)
    )

    foreach ($def in $Definitions) {
        $leaves    = @($def.Block | ForEach-Object { Split-Path $_ -Leaf })
        $procPaths = @($Processes | Where-Object { $leaves -contains $_.Name } | ForEach-Object { $_.Path })
        $install   = Find-Launcher -Definition $def -ProcessPath $procPaths
        $myRules   = @($Rules | Where-Object { $_.LauncherId -eq $def.Id })

        $running = @()
        if ($install) {
            # Processes started through a junction report the junction path, so resolve before comparing.
            $watched = @($install.Exes) + @($install.CloseExes)
            $watchedLeaves = @($watched | ForEach-Object { Split-Path $_ -Leaf })
            $running = @($Processes | Where-Object {
                    ($watchedLeaves -contains $_.Name) -and ($watched -contains (Resolve-RealPath $_.Path))
                })
        }

        $status = [pscustomobject]@{
            Id         = $def.Id
            Name       = $def.Name
            Definition = $def
            Installed  = [bool]$install
            Root       = $(if ($install) { $install.Root })
            Exes       = $(if ($install) { @($install.Exes) } else { @() })
            Rules      = $myRules
            Running    = $running
            State      = 'Online'
        }
        if ($myRules.Count) {
            $programs = @($myRules | ForEach-Object { $_.Program })
            $status.State = if (Test-SamePathSet $programs (Get-DesiredProgram $status)) { 'Offline' } else { 'NeedsRepair' }
        }
        $status
    }
}

function Get-DesiredProgram {
    <#
    Programs an offline launcher should have rules for. If the launcher is found, its
    current exes; otherwise keep the rules that still point at an existing file, so a
    temporary detection failure never silently takes a launcher back online.
    #>
    param([Parameter(Mandatory)]$Status)
    if ($Status.Installed) { return @($Status.Exes) }
    @($Status.Rules | Where-Object { Test-Path -LiteralPath $_.Program -PathType Leaf } | ForEach-Object { $_.Program })
}
