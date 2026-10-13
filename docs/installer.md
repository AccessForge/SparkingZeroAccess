# Installing the standalone repair package

These helpers belong to the standalone repair ZIP. They do not install from a
plain source checkout or replace AccessForge's own installer. Maintainers can
build the ZIP from a clean repository using
`python helpers/Build-RepairPackage.py --output standalone-repair`.
It includes the tested loader, configuration, UTOC bypass and complete runtime.

Extract the complete ZIP, close Sparking! ZERO, then run `Install.cmd`.
It opens Windows PowerShell in STA mode for the standard file picker and keeps
the result visible until a key is pressed. Spaces and punctuation in the
extracted folder name are supported.

`Game-Install-Location.ps1` reads Steam's registry installation locations and
the modern or older `libraryfolders.vdf` files. In each library it checks the
manifest for Steam app 1790600 and validates the shipping executable. It also
checks the two known game-folder names when the manifest is missing. It skips
disconnected library drives, rejects a manifest directory containing path
separators, and merges duplicate paths without merging distinct installations.

One installation is selected automatically. Multiple installations are listed
for a numbered choice. If no game is found, a standard Windows file picker lets
the user select `SparkingZERO.exe` or `SparkingZERO-Win64-Shipping.exe`. Neither
discovery nor cancellation writes to game directories. No full-drive scan or
registry modification is used, and no user's install path is bundled.

The installer then keeps its existing protections: refuse a running game,
back up replaced files, disable an old root UE4SS.dll, preserve other mod
registry entries, and hash-check copied payload files. Compatibility with a
different executable remains unverified and is reported as such.
The recognized executable hashes cover the earlier 3020.019.003.012.013 build
and the Steam 3022.021.003.012.015 build tested on October 4, 2026. Recognition
means the installed reader has been exercised on that executable; it does not
mean every screen or DLC has been validated.

For support or automated use, `Install-Repair.ps1 -GameDirectory <folder>`
still accepts an explicit target. `Install-Repair.ps1 -DetectOnly` lists
detected game folders without displaying a picker or installing anything.

Run `tests/install_discovery_test.ps1`, `tests/install_repair_test.ps1` and
`tests/install_launcher_test.ps1` with Windows PowerShell 5.1. They use isolated
fixture files. The launcher test runs a harmless substitute installer, including
from a folder with spaces, brackets, an ampersand and an exclamation mark.
All 18 checks pass in Windows PowerShell 5.1. Payload verification uses streaming
SHA-256 from .NET, including a fixture where Get-FileHash is unavailable.
