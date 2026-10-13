# Language option reading

The language rows are `WBP_OBJ_Option_List_013_Lang_C` instances named
`LocalizationTextButton` and `LocalizationVoiceButton`. Their selected value is
the texture in `IMG_Lang.Brush.ResourceObject`, not a text caption. The reader
uses this displayed texture on the game thread. It does not infer selection from
pressed keys, a saved setting, or the currently applied interface language.

The mapping below was verified against a live native-property capture on
2026-10-03. The executable SHA256 was
`e54e79e756f79719f09915078a37b6e87c23d32ecaaaa2f485d1a048ba198e55`.
The capture is saved outside the repository in
`../evidence/language-names-20261003.txt`.

For the display-language row, each `ItemEntries` element contains `Value1` and
`DisplayName`. `Value1` is a zero-based index into the parent language manager's
`InstallLangCode`. That language code matches `ImageTextureList.ImageNo`, whose
`ImageTextures` identifies the texture. Ghidra confirmed this indexing in the
native language-change handler at `0x142B20F10`. These addresses document the
research only; the mod uses no hardcoded memory offsets.

All resources have the directory `/Game/SS/UI/Title/OBJ/Texture/` and the asset
prefix `T_UI_Title_LanguageSelect_`. The native code, suffix, and captured name are:

- 1, `jp`: 日本語
- 2, `en`: English
- 4, `es`: Español (España)
- 5, `la`: Español (América Latina)
- 6, `de`: Deutsch
- 7, `fr`: Français
- 9, `it`: Italiano
- 10, `ko`: 한국어
- 13, `bp`: Português (Brasil)
- 14, `ru`: Русский
- 15, `zhcn`: 中文 (简体)
- 16, `zhtw`: 中文 (繁體)
- 21, `pl`: Polish
- 23, `ar`: العربية
- 28, `th`: ภาษาไทย
- 30, `id`: Bahasa Indonesia

The voice row has empty `DisplayName` fields, and uses local image numbers 0 and
1 for the same `jp` and `en` textures. Reading the exact displayed resource works
for both rows without confusing these different numbering schemes.

Spoken names use English equivalents, consistent with the existing reader's
labels and usable with an English speech voice. Spanish regions, Portuguese
Brazil, and the two Chinese writing systems remain distinct. Unknown resources
produce an explicit unavailable announcement and a diagnostic; they never get
an inferred name from an image number. Names are keyed by full resource path.

The focus handler speaks the label and current value, then polls for value
changes through the existing game-thread scheduler. Losing focus, entering a
specialist screen, and map transitions discard the reader. It performs no
global widget scans while polling the selected image.
