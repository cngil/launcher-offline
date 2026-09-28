function Resolve-RealPath {
    <#
    .SYNOPSIS
    Follows junctions and symlinks in every segment of a path.
    Firewall rules must point at the real file; package managers like Scoop expose
    apps through a "current" junction that changes target on every update.
    #>
    param([Parameter(Mandatory)][string]$Path)

    $full  = [IO.Path]::GetFullPath($Path)
    $root  = [IO.Path]::GetPathRoot($full)
    $parts = $full.Substring($root.Length).Split([char[]]'\/', [StringSplitOptions]::RemoveEmptyEntries)

    $current = $root
    foreach ($part in $parts) {
        $current = Join-Path $current $part
        $item = Get-Item -LiteralPath $current -Force -ErrorAction SilentlyContinue
        if ($item -and $item.LinkType -in 'Junction', 'SymbolicLink') {
            $target = @($item.Target)[0]
            if ($target) {
                if (-not [IO.Path]::IsPathRooted($target)) {
                    $target = Join-Path (Split-Path $current -Parent) $target
                }
                $current = Resolve-RealPath $target
            }
        }
    }
    $current
}

function Get-ScoopRoot {
    $roots = @()
    if ($env:SCOOP) { $roots += $env:SCOOP }
    if ($env:USERPROFILE) { $roots += Join-Path $env:USERPROFILE 'scoop' }
    if ($env:SCOOP_GLOBAL) { $roots += $env:SCOOP_GLOBAL }
    if ($env:ProgramData) { $roots += Join-Path $env:ProgramData 'scoop' }
    $roots | Select-Object -Unique
}

function Test-SamePathSet {
    param([string[]]$Left, [string[]]$Right)
    $a = @($Left | Where-Object { $_ } | ForEach-Object { $_.ToLowerInvariant() } | Sort-Object -Unique)
    $b = @($Right | Where-Object { $_ } | ForEach-Object { $_.ToLowerInvariant() } | Sort-Object -Unique)
    ($a -join '|') -eq ($b -join '|')
}
