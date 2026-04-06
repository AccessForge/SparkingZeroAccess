# Known Issues

## Mod Issues
- UE4SS GUI debug window disabled (GuiConsoleVisible=0) for accessibility
- Team slot character names use texture ID lookup — new DLC characters need to be added to chara_names.lua
- FindFirstOf may return CDO (class default object) instead of live instance — always check for "Transient" in path or use FindAllOf with path filtering
