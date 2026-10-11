$ErrorActionPreference = 'Stop'
$parent = (Resolve-Path -LiteralPath $PSScriptRoot).ProviderPath
$fixture = Join-Path $parent ('launcher-test-[' + [guid]::NewGuid().ToString('N') + '] spaces & exclamation!')
try {
    New-Item -ItemType Directory -Path $fixture | Out-Null
    $launcher = Join-Path $fixture 'Install.cmd'
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\helpers\Install.cmd') -Destination $launcher
    $stub = @'
$message = 'Started through the package launcher; apartment=' + [Threading.Thread]::CurrentThread.GetApartmentState()
[IO.File]::WriteAllText((Join-Path $PSScriptRoot 'launch-result.txt'), $message)
exit 7
'@
    [IO.File]::WriteAllText((Join-Path $fixture 'Install-Repair.ps1'),$stub)
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $env:ComSpec
    $info.Arguments = '/d /s /c ""' + $launcher + '" <nul"'
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $process = [Diagnostics.Process]::Start($info)
    try {
        if (-not $process.WaitForExit(15000)) { $process.Kill(); throw 'Launcher fixture did not finish.' }
        $output = $process.StandardOutput.ReadToEnd() + $process.StandardError.ReadToEnd()
        $result = Get-Content -LiteralPath (Join-Path $fixture 'launch-result.txt') -Raw
        if ($process.ExitCode -ne 7 -or -not $result.Contains('apartment=STA')) { throw ('Launcher failed: ' + $output) }
        if (-not $output.Contains('Installation did not finish.')) { throw 'Launcher hid the installer failure.' }
        Write-Output 'PASS: double-click launcher handles spaces, brackets, ampersands and exclamation marks; uses STA and preserves errors'
    } finally { $process.Dispose() }
} finally {
    if (Test-Path -LiteralPath $fixture) {
        $resolved = (Resolve-Path -LiteralPath $fixture).ProviderPath
        if ($resolved -ne $fixture -or -not $resolved.StartsWith($parent + '\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Refusing cleanup outside launcher fixture.' }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
