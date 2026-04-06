# Dependencies

Bundled dependencies installed by AccessForge alongside the mod.

## utoc-bypass.zip

UTOC Signature Bypass — required for Sparking! ZERO to load modded content. Without this patch, the game's signature verification rejects any modified or added files.

Contains:
- `dsound.dll` — DLL proxy loader
- `plugins/DBSparkingZeroUTOCBypass.asi` — the bypass plugin

These are extracted next to the game executable by AccessForge (`type: patch` in the manifest).
