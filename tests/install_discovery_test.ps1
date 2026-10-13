$ErrorActionPreference = 'Stop'
$helper = Join-Path $PSScriptRoot '..\helpers\Game-Install-Location.ps1'
if (-not (Test-Path -LiteralPath $helper)) { throw 'Automatic game discovery is not implemented.' }
. $helper
$testParent = (Resolve-Path -LiteralPath $PSScriptRoot).ProviderPath
$testRoot = Join-Path $testParent ('discovery-test-' + [guid]::NewGuid().ToString('N'))
function Assert-Test([bool]$value, [string]$message) { if (-not $value) { throw $message } }
function Write-Fixture([string]$path, [string]$text) {
    New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
    [IO.File]::WriteAllText($path, $text)
}
function Game-Fixture([string]$root) {
    Write-Fixture (Join-Path $root 'SparkingZERO\Binaries\Win64\SparkingZERO-Win64-Shipping.exe') 'fixture; never executed'
    Write-Fixture (Join-Path $root 'SparkingZERO.exe') 'fixture; never executed'
}
try {
    $steam = Join-Path $testRoot 'Steam client'
    $library = Join-Path $testRoot 'Library [games] & friends!'
    $game = Join-Path $library 'steamapps\common\Custom game folder'
    Game-Fixture $game
    $escaped = $library.Replace('\','\\')
    Write-Fixture (Join-Path $steam 'steamapps\libraryfolders.vdf') ('"libraryfolders" {' + "`n" + '"1" {' + "`n" + '"path" "' + $escaped + '"' + "`n}" + "`n}")
    Write-Fixture (Join-Path $library 'steamapps\appmanifest_1790600.acf') ('"AppState" {' + "`n" + '"appid" "1790600"' + "`n" + '"installdir" "Custom game folder"' + "`n}")
    $found = @(Get-SparkingZeroInstallations -SteamRoots @($steam))
    Assert-Test ($found.Count -eq 1 -and $found[0] -eq $game) 'Secondary library with escaped/special characters was not found.'
    Write-Output 'PASS: modern Steam libraries and manifest install names work without hardcoded game paths'

    Write-Fixture (Join-Path $steam 'config\libraryfolders.vdf') ('"libraryfolders" {' + "`n" + '"1" "' + $escaped + '"' + "`n}")
    $found = @(Get-SparkingZeroInstallations -SteamRoots @($steam,$steam.ToUpperInvariant(),$library))
    Assert-Test ($found.Count -eq 1) 'Duplicate libraries produced duplicate choices.'
    Write-Output 'PASS: duplicate registry and library entries are merged case-insensitively'

    $unused = @('Z','W','V','U','T') | Where-Object { -not (Get-PSDrive -Name $_ -ErrorAction SilentlyContinue) } | Select-Object -First 1
    if (-not $unused) { throw 'No unused drive letter available for the offline-library fixture.' }
    $offline = $unused + ':\Offline Steam Library'
    Write-Fixture (Join-Path $steam 'config\libraryfolders.vdf') ('"libraryfolders" {' + "`n" + '"1" {' + "`n" + '"path" "' + $offline.Replace('\','\\') + '"' + "`n}`n}")
    $found = @(Get-SparkingZeroInstallations -SteamRoots @($steam,$offline))
    Assert-Test ($found.Count -eq 1 -and $found[0] -eq $game) 'Offline Steam drives prevented detection of the installed game.'
    Write-Output 'PASS: disconnected Steam library drives do not prevent installation discovery'

    $legacySteam = Join-Path $testRoot 'Old client'
    Write-Fixture (Join-Path $legacySteam 'config\libraryfolders.vdf') ('"LibraryFolders" {' + "`n" + '"1" "' + $escaped + '"' + "`n}")
    Assert-Test (@(Get-SparkingZeroInstallations -SteamRoots @($legacySteam)).Count -eq 1) 'Legacy library format failed.'
    Write-Output 'PASS: older Steam library configuration is supported'

    $looseLibrary = Join-Path $testRoot 'No manifest library'
    $looseGame = Join-Path $looseLibrary 'steamapps\common\DRAGON BALL - Sparking! ZERO'
    Game-Fixture $looseGame
    $found = @(Get-SparkingZeroInstallations -SteamRoots @($looseLibrary))
    Assert-Test ($found.Count -eq 1 -and $found[0] -eq $looseGame) 'An existing game without an appmanifest was missed.'
    Write-Output 'PASS: recognized game folders are found even when the Steam appmanifest is missing'

    $missing = Join-Path $testRoot 'Stale library'
    Write-Fixture (Join-Path $missing 'steamapps\appmanifest_1790600.acf') ('"appid" "1790600"' + "`n" + '"installdir" "Missing game"')
    Assert-Test (@(Get-SparkingZeroInstallations -SteamRoots @($missing)).Count -eq 0) 'A stale manifest became an install target.'
    $outside = Join-Path $testRoot 'Outside'
    Game-Fixture $outside
    Write-Fixture (Join-Path $missing 'steamapps\appmanifest_1790600.acf') ('"appid" "1790600"' + "`n" + '"installdir" "..\..\..\Outside"')
    Assert-Test (@(Get-SparkingZeroInstallations -SteamRoots @($missing)).Count -eq 0) 'A traversing manifest became an install target.'
    Write-Output 'PASS: stale and traversing manifest entries are rejected'

    $found = @(Get-SparkingZeroInstallations -SteamRoots @($steam,$looseLibrary))
    Assert-Test ($found.Count -eq 2) 'Distinct installed copies were silently discarded.'
    Write-Output 'PASS: multiple installations remain separate choices'

    Assert-Test ((Get-SparkingZeroRootFromExecutable (Join-Path $game 'SparkingZERO.exe')) -eq $game) 'Root launcher selection failed.'
    Assert-Test ((Get-SparkingZeroRootFromExecutable (Join-Path $game 'SparkingZERO\Binaries\Win64\SparkingZERO-Win64-Shipping.exe')) -eq $game) 'Shipping executable selection failed.'
    Write-Fixture (Join-Path $game 'Unrelated.exe') 'fixture'
    Assert-Test ($null -eq (Get-SparkingZeroRootFromExecutable (Join-Path $game 'Unrelated.exe'))) 'An unrelated executable was accepted.'
    Write-Output 'PASS: browsing accepts either real game executable and rejects unrelated files'

    $selected = Resolve-SparkingZeroInstallation -Candidates @($game) -Browse { throw 'Picker should not open' }
    Assert-Test ($selected -eq $game) 'A single installation was not selected automatically.'
    $selected = Resolve-SparkingZeroInstallation -Candidates @() -Browse { Join-Path $game 'SparkingZERO.exe' }
    Assert-Test ($selected -eq $game) 'Browse fallback failed.'
    $selected = Resolve-SparkingZeroInstallation -Candidates @($game,$looseGame) -Choose { param($choices) '2' } -Browse { throw 'Picker should not open' }
    Assert-Test ($selected -eq $looseGame) 'The multiple-install choice was ignored.'
    Write-Output 'PASS: one install is automatic; fallback browsing and numbered selection require no typed path'

    $cancelled = $false
    try { Resolve-SparkingZeroInstallation -Candidates @() -Browse { $null } | Out-Null }
    catch { $cancelled = $_.Exception.Message -like 'Installation cancelled*' }
    Assert-Test $cancelled 'Cancelling the picker was not handled.'
    Assert-Test (@(Get-ChildItem -LiteralPath $testRoot -Recurse -Filter 'SparkingZeroAccess-repair-backups').Count -eq 0) 'Discovery created installation backups.'
    Write-Output 'PASS: discovery and cancellation do not write to game installations'
} finally {
    if (Test-Path -LiteralPath $testRoot) {
        $resolved = (Resolve-Path -LiteralPath $testRoot).ProviderPath
        if ($resolved -ne $testRoot -or -not $resolved.StartsWith($testParent + '\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Refusing cleanup outside fixture directory.' }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
