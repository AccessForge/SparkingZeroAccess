# Dependencies

Bundled dependencies installed by AccessForge alongside the mod.

## utoc-bypass.zip

UTOC Signature Bypass — required for Sparking! ZERO to load modded content. Without this patch, the game's signature verification rejects any modified or added files.

Contains:
- `dsound.dll` — DLL proxy loader
- `plugins/DBSparkingZeroUTOCBypass.asi` — the bypass plugin

These are extracted next to the game executable by AccessForge (`type: patch` in the manifest).

## ue4ss-tested-1152.zip

The standalone repair builder uses this tested UE4SS loader/configuration
bundle. It retains the loader's MIT license and a file-hash manifest.
See [its contents and AccessForge integration limits](ue4ss-tested-1152.md).
It is not declared as an automatic patch dependency because the current
AccessForge loader layout and legacy-DLL migration need separate integration.
