$ErrorActionPreference = 'Stop'
$testParent = (Resolve-Path -LiteralPath $PSScriptRoot).ProviderPath
$testRoot = Join-Path $testParent ('installer-test-' + [guid]::NewGuid().ToString('N'))
$packageDir = Join-Path $testRoot 'package'
$fixtureGame = Join-Path $testRoot 'game'
$fixtureBin = Join-Path $fixtureGame 'SparkingZERO\Binaries\Win64'
$installer = Join-Path $packageDir 'Install-Repair.ps1'

function Write-Fixture([string]$path, [string]$content) {
    New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
    [IO.File]::WriteAllText($path, $content)
}
function Assert-Test([bool]$condition, [string]$message) {
    if (-not $condition) { throw $message }
}
# Only this isolated test process uses the simulated process list.
function Get-Process {
    [CmdletBinding()]
    param([string[]]$Name)
    [pscustomobject]@{ ProcessName = 'SparkingZERO' }
}
# The installer must not depend on this optional script-based shell command.
function Get-FileHash { throw 'Get-FileHash is unavailable in this fixture.' }

try {
    New-Item -ItemType Directory -Path $packageDir -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\helpers\Install-Repair.ps1') -Destination $installer
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\helpers\Game-Install-Location.ps1') -Destination $packageDir
    $payload = @{
        'dwmapi.dll' = 'new proxy fixture'
        'ue4ss\UE4SS.dll' = 'new loader fixture'
        'ue4ss\UE4SS-settings.ini' = 'HookInitGameState = 0'
        'ue4ss\Mods\mods.txt' = 'SparkingZeroAccess : 1'
        'ue4ss\Mods\SparkingZeroAccess\Scripts\language_options.lua' = 'return {}'
    }
    foreach ($relative in $payload.Keys) { Write-Fixture (Join-Path $packageDir ('Win64\' + $relative)) $payload[$relative] }
    Write-Fixture (Join-Path $fixtureBin 'SparkingZERO-Win64-Shipping.exe') 'fixture, never executed'
    Write-Fixture (Join-Path $fixtureBin 'UE4SS.dll') 'old root loader fixture'
    Write-Fixture (Join-Path $fixtureBin 'dwmapi.dll') 'old proxy fixture'
    $registry = Join-Path $fixtureBin 'ue4ss\Mods\mods.txt'
    Write-Fixture $registry "OtherMod : 1`r`nSparkingZeroAccess : 0`r`n"
    $subtitlePreference = Join-Path $fixtureBin 'SparkingZeroAccess-subtitles.ini'
    Write-Fixture $subtitlePreference "AutomaticSubtitles=false`n"

    $blocked = $false
    try { & $installer -GameDirectory $fixtureGame | Out-Null }
    catch { $blocked = $_.Exception.Message -like 'Close Sparking*' }
    Assert-Test $blocked 'Installer did not stop for a running game.'
    Assert-Test ((Get-Content -LiteralPath (Join-Path $fixtureBin 'dwmapi.dll') -Raw) -eq 'old proxy fixture') 'Blocked install changed files.'
    Write-Output 'PASS: a running game prevents all installation writes'

    function Get-Process {
        [CmdletBinding()]
        param([string[]]$Name)
    }
    & $installer -GameDirectory $fixtureGame 3>$null | Out-Null
    $backup = @(Get-ChildItem -LiteralPath (Join-Path $fixtureGame 'SparkingZeroAccess-repair-backups') -Directory)[0]
    Assert-Test ((Get-Content -LiteralPath (Join-Path $backup.FullName 'Win64\dwmapi.dll') -Raw) -eq 'old proxy fixture') 'Original proxy backup missing.'
    Assert-Test ((Get-Content -LiteralPath (Join-Path $backup.FullName 'Win64\UE4SS.dll') -Raw) -eq 'old root loader fixture') 'Original loader backup missing.'
    Assert-Test (-not (Test-Path -LiteralPath (Join-Path $fixtureBin 'UE4SS.dll'))) 'Legacy root DLL still active.'
    Assert-Test (@(Get-ChildItem -LiteralPath $fixtureBin -Filter 'UE4SS.dll.pre-repair-*.disabled').Count -eq 1) 'Legacy DLL was not preserved in place.'
    Assert-Test ((Get-Content -LiteralPath (Join-Path $fixtureBin 'ue4ss\UE4SS.dll') -Raw) -eq 'new loader fixture') 'New loader was not installed.'
    Write-Output 'PASS: original files are backed up and legacy loader is disabled'
    $backupManifest = Get-Content -LiteralPath (Join-Path $backup.FullName 'backup-manifest.json') -Raw | ConvertFrom-Json
    Assert-Test ($backupManifest.gameExecutableSHA256 -eq 'CD2C9C08109990F1425F4A536B6D3325F38DBD619E0035BCE7473AE3C8FC8239') 'Executable SHA-256 does not match the independent fixture digest.'
    Write-Output 'PASS: verified streaming SHA-256 works without Get-FileHash'

    $list = Get-Content -LiteralPath $registry -Raw
    Assert-Test ($list.Contains('OtherMod : 1') -and $list.Contains('SparkingZeroAccess : 1')) 'Mod registry was not merged.'
    & $installer -GameDirectory $fixtureGame 3>$null | Out-Null
    $list = Get-Content -LiteralPath $registry -Raw
    Assert-Test ([regex]::Matches($list, 'SparkingZeroAccess\s*:\s*1').Count -eq 1) 'Repeated installation duplicated the mod entry.'
    Assert-Test ($list.Contains('OtherMod : 1')) 'Repeated installation removed another mod.'
    Write-Output 'PASS: other mod entries survive installation and reinstall'
    Assert-Test ((Get-Content -LiteralPath $subtitlePreference -Raw) -eq "AutomaticSubtitles=false`n") 'Installation overwrote the subtitle speech preference.'
    Write-Output 'PASS: the saved subtitle speech choice survives installation and reinstall'

    [IO.File]::WriteAllText($registry, '')
    & $installer -GameDirectory $fixtureGame 3>$null | Out-Null
    Assert-Test ((Get-Content -LiteralPath $registry -Raw).Contains('SparkingZeroAccess : 1')) 'Empty mod registry was not initialized.'
    Write-Output 'PASS: an empty existing mod registry is handled'

    # Only the copied helper in this fixture receives simulated Steam roots.
    # Detection, executable validation and installation use the real code.
    $autoSteam = Join-Path $testRoot 'automatic Steam library'
    $autoGame = Join-Path $autoSteam 'steamapps\common\DRAGON BALL - Sparking! ZERO'
    $autoBin = Join-Path $autoGame 'SparkingZERO\Binaries\Win64'
    Write-Fixture (Join-Path $autoBin 'SparkingZERO-Win64-Shipping.exe') 'fixture; never executed'
    $mock = "`r`nfunction Get-SteamRootLocations { '" + $autoSteam.Replace("'", "''") + "' }`r`n"
    Add-Content -LiteralPath (Join-Path $packageDir 'Game-Install-Location.ps1') -Value $mock -Encoding UTF8
    $detected = @(& $installer -DetectOnly)
    Assert-Test ($detected.Count -eq 1 -and $detected[0] -eq $autoGame) 'Fixture-only automatic detection failed; installation not attempted.'
    Assert-Test (-not (Test-Path -LiteralPath (Join-Path $autoGame 'SparkingZeroAccess-repair-backups'))) 'DetectOnly modified the fixture.'
    & $installer 3>$null | Out-Null
    Assert-Test ((Get-Content -LiteralPath (Join-Path $autoBin 'ue4ss\UE4SS.dll') -Raw) -eq 'new loader fixture') 'No-argument installation did not copy the payload.'
    Assert-Test (Test-Path -LiteralPath (Join-Path $autoGame 'SparkingZeroAccess-repair-backups')) 'Automatic installation did not create backups.'
    Write-Output 'PASS: no-argument installation detects the fixture and installs with backups; DetectOnly makes no changes'
} finally {
    if (Test-Path -LiteralPath $testRoot) {
        $resolvedTestRoot = (Resolve-Path -LiteralPath $testRoot).ProviderPath
        if ($resolvedTestRoot -ne $testRoot -or -not $resolvedTestRoot.StartsWith($testParent + '\', [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Refusing cleanup outside the exact test directory.'
        }
        Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force
    }
}
