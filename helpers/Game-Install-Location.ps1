# Read Steam configuration; never scan whole drives or change the registry.
function ConvertTo-InstallFolder([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path) -or -not [IO.Path]::IsPathRooted($Path)) { return $null }
    try {
        $full = [IO.Path]::GetFullPath($Path)
        if ($full.Length -gt [IO.Path]::GetPathRoot($full).Length) { $full = $full.TrimEnd('\','/') }
        return $full
    } catch { return $null }
}

function Test-SparkingZeroFolder([string]$Path) {
    if (-not $Path) { return $false }
    return Test-Path -LiteralPath (Join-Path $Path 'SparkingZERO\Binaries\Win64\SparkingZERO-Win64-Shipping.exe') -PathType Leaf
}

function Get-SteamRootLocations {
    foreach ($entry in @(
        @('HKCU:\Software\Valve\Steam','SteamPath'),
        @('HKLM:\SOFTWARE\WOW6432Node\Valve\Steam','InstallPath'),
        @('HKLM:\SOFTWARE\Valve\Steam','InstallPath')
    )) {
        $record = Get-ItemProperty -LiteralPath $entry[0] -ErrorAction SilentlyContinue
        if ($record -and $record.($entry[1])) { $record.($entry[1]) }
    }
    foreach ($programFolder in @(${env:ProgramFiles(x86)},$env:ProgramFiles)) {
        if ($programFolder) { Join-Path $programFolder 'Steam' }
    }
}

function ConvertFrom-VdfString([string]$Value) {
    return [regex]::Replace($Value, '\\(["\\])', '$1')
}

function Get-VdfValue([string]$Text, [string]$Key) {
    $pattern = '(?im)^\s*"' + [regex]::Escape($Key) + '"\s*"((?:\\.|[^"\\])*)"'
    $match = [regex]::Match($Text, $pattern)
    if ($match.Success) { return ConvertFrom-VdfString $match.Groups[1].Value }
    return $null
}

function Get-SparkingZeroInstallations {
    param([AllowEmptyCollection()][string[]]$SteamRoots)
    if (-not $PSBoundParameters.ContainsKey('SteamRoots')) { $SteamRoots = @(Get-SteamRootLocations) }
    $libraries = [Collections.Generic.List[string]]::new()
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($root in $SteamRoots) {
        $folder = ConvertTo-InstallFolder $root
        if ($folder -and $seen.Add($folder)) { $libraries.Add($folder) }
    }
    # Read both client layouts. Numeric values inside the apps block are not
    # paths, so they cannot become candidates in the older VDF format.
    foreach ($root in @($libraries.ToArray())) {
        if (-not [IO.Directory]::Exists($root)) { continue }
        foreach ($relative in @('steamapps\libraryfolders.vdf','config\libraryfolders.vdf')) {
            $config = Join-Path $root $relative
            if (-not (Test-Path -LiteralPath $config -PathType Leaf)) { continue }
            try { $text = Get-Content -LiteralPath $config -Raw -Encoding UTF8 }
            catch { Write-Verbose "Cannot read Steam library configuration: $config"; continue }
            foreach ($match in [regex]::Matches($text, '(?im)^\s*"(?:path|\d+)"\s*"((?:\\.|[^"\\])*)"')) {
                $folder = ConvertTo-InstallFolder (ConvertFrom-VdfString $match.Groups[1].Value)
                if ($folder -and $seen.Add($folder)) { $libraries.Add($folder) }
            }
        }
    }
    $found = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($library in $libraries) {
        if (-not [IO.Directory]::Exists($library)) { continue }
        $common = Join-Path $library 'steamapps\common'
        $names = [Collections.Generic.List[string]]::new()
        $manifest = Join-Path $library 'steamapps\appmanifest_1790600.acf'
        if (Test-Path -LiteralPath $manifest -PathType Leaf) {
            try {
                $text = Get-Content -LiteralPath $manifest -Raw -Encoding UTF8
                $directory = Get-VdfValue $text 'installdir'
                if ((Get-VdfValue $text 'appid') -eq '1790600' -and $directory -and
                    $directory -notin @('.','..') -and
                    $directory.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -lt 0) {
                    $names.Add($directory)
                }
            } catch { Write-Verbose "Cannot read game appmanifest: $manifest" }
        }
        # Some existing copies have no appmanifest. Validate the executable in
        # the two known game-folder names within each registered library.
        $names.Add('DRAGON BALL - Sparking! ZERO')
        $names.Add('DRAGON BALL Sparking! ZERO')
        foreach ($name in $names) {
            $game = ConvertTo-InstallFolder (Join-Path $common $name)
            if ((Test-SparkingZeroFolder $game) -and $found.Add($game)) { $game }
        }
    }
}

function Get-SparkingZeroRootFromExecutable([string]$Path) {
    if (-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    $file = (Get-Item -LiteralPath $Path).FullName
    $folder = [IO.Path]::GetDirectoryName($file)
    switch ([IO.Path]::GetFileName($file)) {
        'SparkingZERO.exe' { $root = $folder }
        'SparkingZERO-Win64-Shipping.exe' {
            $root = [IO.Path]::GetDirectoryName([IO.Path]::GetDirectoryName([IO.Path]::GetDirectoryName($folder)))
        }
        default { return $null }
    }
    if (Test-SparkingZeroFolder $root) { return $root }
    return $null
}

function Show-SparkingZeroFilePicker {
    Add-Type -AssemblyName System.Windows.Forms
    $picker = New-Object System.Windows.Forms.OpenFileDialog
    try {
        $picker.Title = 'Choose SparkingZERO.exe in your game folder'
        $picker.Filter = 'Sparking! ZERO executables|SparkingZERO.exe;SparkingZERO-Win64-Shipping.exe'
        $picker.CheckFileExists = $true
        $picker.Multiselect = $false
        $picker.RestoreDirectory = $true
        if ($picker.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { return $picker.FileName }
    } finally { $picker.Dispose() }
    return $null
}

function Resolve-SparkingZeroInstallation {
    param(
        [AllowEmptyCollection()][string[]]$Candidates,
        [scriptblock]$Browse = { Show-SparkingZeroFilePicker },
        [scriptblock]$Choose = { param($choices) Read-Host 'Enter an installation number, B to browse, or Q to cancel' }
    )
    if ($Candidates.Count -eq 1) { return $Candidates[0] }
    if ($Candidates.Count -gt 1) {
        Write-Host 'More than one Sparking! ZERO installation was found:'
        for ($i = 0; $i -lt $Candidates.Count; $i++) { Write-Host ('{0}. {1}' -f ($i+1),$Candidates[$i]) }
        while ($true) {
            $choice = [string](& $Choose $Candidates)
            if ($choice -eq 'q' -or -not $choice) { throw 'Installation cancelled. No game files were changed.' }
            if ($choice -eq 'b') { break }
            $index = 0
            if ([int]::TryParse($choice,[ref]$index) -and $index -ge 1 -and $index -le $Candidates.Count) { return $Candidates[$index-1] }
            Write-Host 'Choose one of the displayed numbers, B, or Q.'
        }
    } else {
        Write-Host 'No installation found in Steam libraries. Browse to the game and select SparkingZERO.exe.'
    }
    $selected = & $Browse
    if (-not $selected) { throw 'Installation cancelled. No game files were changed.' }
    $root = Get-SparkingZeroRootFromExecutable $selected
    if (-not $root) { throw 'That file is not a valid Sparking! ZERO installation. Select SparkingZERO.exe in the game folder.' }
    return $root
}
