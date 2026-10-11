param(
    [string]$GameDirectory,
    [switch]$DetectOnly
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Game-Install-Location.ps1')
function Get-RepairFileHash([string]$LiteralPath) {
    # Streaming SHA-256 also works when Windows PS cannot resolve Get-FileHash.
    $inputFile = [IO.File]::OpenRead($LiteralPath)
    $hasher = [Security.Cryptography.SHA256]::Create()
    try {
        return [BitConverter]::ToString($hasher.ComputeHash($inputFile)).Replace('-', '')
    } finally {
        $inputFile.Dispose()
        $hasher.Dispose()
    }
}
if ($DetectOnly) {
    Get-SparkingZeroInstallations
    return
}
if (Get-Process -Name 'SparkingZERO', 'SparkingZERO-Win64-Shipping' -ErrorAction SilentlyContinue) {
    throw 'Close Sparking! ZERO before installing the repair.'
}
if (-not $GameDirectory) {
    $GameDirectory = Resolve-SparkingZeroInstallation -Candidates @(Get-SparkingZeroInstallations)
}
$gameRoot = (Resolve-Path -LiteralPath $GameDirectory).ProviderPath
$gameBin = Join-Path $gameRoot 'SparkingZERO\Binaries\Win64'
$gameExe = Join-Path $gameBin 'SparkingZERO-Win64-Shipping.exe'
$payloadRoot = Join-Path $PSScriptRoot 'Win64'
if (-not (Test-Path -LiteralPath $gameExe -PathType Leaf)) {
    throw 'Choose the game folder containing SparkingZERO\Binaries\Win64.'
}
if (-not (Test-Path -LiteralPath (Join-Path $payloadRoot 'ue4ss\Mods\SparkingZeroAccess\Scripts\language_options.lua'))) {
    throw 'Keep Install-Repair.ps1 beside the complete Win64 folder from the repair package.'
}
Write-Host ('Installing into: ' + $gameRoot)

$validatedHashes = @(
    'E54E79E756F79719F09915078A37B6E87C23D32ECAAAA2F485D1A048BA198E55', # 3020.019.003.012.013
    '6DB7002A8FA66A1309B01037D8A9A8C678A8ECD35B72D4C6AFAC550A74371657'  # 3022.021.003.012.015
)
$gameHash = Get-RepairFileHash -LiteralPath $gameExe
if ($gameHash -notin $validatedHashes) {
    Write-Warning 'This game executable differs from the build used for this repair. Compatibility is unverified.'
}

$stamp = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
$backupRoot = Join-Path $gameRoot ('SparkingZeroAccess-repair-backups\' + $stamp)
New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
$records = [System.Collections.Generic.List[object]]::new()

function Backup-RepairTarget([string]$relative) {
    $destination = Join-Path $gameBin $relative
    $existed = Test-Path -LiteralPath $destination -PathType Leaf
    if ($existed) {
        $savedPath = Join-Path $backupRoot ('Win64\' + $relative)
        New-Item -ItemType Directory -Path (Split-Path -Parent $savedPath) -Force | Out-Null
        Copy-Item -LiteralPath $destination -Destination $savedPath
    }
    $records.Add([ordered]@{ path = $relative; existed = $existed })
}

# Back up all destinations before changing loader files or the mod registry.
$payloadFiles = @(Get-ChildItem -LiteralPath $payloadRoot -Recurse -File)
foreach ($file in $payloadFiles) {
    $relative = $file.FullName.Substring($payloadRoot.Length + 1)
    Backup-RepairTarget $relative
}
$legacyDll = Join-Path $gameBin 'UE4SS.dll'
$disabledLegacyName = $null
if (Test-Path -LiteralPath $legacyDll -PathType Leaf) {
    Backup-RepairTarget 'UE4SS.dll'
    $disabledLegacyName = 'UE4SS.dll.pre-repair-' + $stamp + '.disabled'
}
[ordered]@{
    gameDirectory = $gameRoot
    gameExecutableSHA256 = $gameHash
    disabledLegacyName = $disabledLegacyName
    files = @($records.ToArray())
} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $backupRoot 'backup-manifest.json') -Encoding UTF8

$modsPath = Join-Path $gameBin 'ue4ss\Mods\mods.txt'
[string]$modsText = if (Test-Path -LiteralPath $modsPath -PathType Leaf) { Get-Content -LiteralPath $modsPath -Raw } else { '' }
if ($null -eq $modsText) { $modsText = '' }
if ($disabledLegacyName) {
    Move-Item -LiteralPath $legacyDll -Destination (Join-Path $gameBin $disabledLegacyName)
}
foreach ($file in $payloadFiles) {
    $relative = $file.FullName.Substring($payloadRoot.Length + 1)
    if ($relative -ieq 'ue4ss\Mods\mods.txt') { continue }
    $destination = Join-Path $gameBin $relative
    New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
    Copy-Item -LiteralPath $file.FullName -Destination $destination -Force
    if ((Get-RepairFileHash -LiteralPath $file.FullName) -ne (Get-RepairFileHash -LiteralPath $destination)) {
        throw ('Installed file failed verification: ' + $relative + '. Backups: ' + $backupRoot)
    }
}
if ($modsText -match '(?m)^\s*SparkingZeroAccess\s*:.*$') {
    $modsText = $modsText -replace '(?m)^\s*SparkingZeroAccess\s*:.*$', 'SparkingZeroAccess : 1'
} else {
    $modsText = $modsText.TrimEnd() + "`r`nSparkingZeroAccess : 1`r`n"
}
[System.IO.File]::WriteAllText($modsPath, $modsText, [System.Text.UTF8Encoding]::new($false))
Write-Output 'SparkingZeroAccess repair installed. Launch the game normally.'
Write-Output ('Original files are backed up in: ' + $backupRoot)
