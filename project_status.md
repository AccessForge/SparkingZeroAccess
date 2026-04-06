# Project Status — Dragon Ball Sparking! ZERO Accessibility Mod

## Project Info
- **Game:** Dragon Ball Sparking! ZERO
- **Engine:** Unreal Engine 5, 64-bit
- **Game path:** C:\Program Files (x86)\Steam\steamapps\common\DRAGON BALL Sparking! ZERO
- **Mod framework:** UE4SS v3.0.1 (dev) + UTOC Signature Bypass
- **Speech library:** UniversalSpeech (via custom Lua C module bridge)
- **Screen reader:** NVDA (confirmed working)
- **User familiarity:** Knows the game well (menus, mechanics)

## Setup Status
- [x] Game installed and first-run complete
- [x] UE4SS v3.0.1 (dev) installed in SparkingZERO\Binaries\Win64
- [x] UTOC Signature Bypass installed (dsound.dll + plugins\DBSparkingZeroUTOCBypass.asi)
- [x] UE4SS settings configured (bUseUObjectArrayCache=false, GraphicsAPI=dx11)
- [x] UniversalSpeech.dll + nvdaControllerClient.dll + ZDSRAPI.dll deployed
- [x] speech_bridge.dll (Lua C module) compiled and deployed
- [x] SparkingZeroAccess Lua mod created and registered in mods.txt
- [x] Speech output confirmed working (F9 test, NVDA spoke text)

## Phase 1: UI Exploration (DONE)
- [x] First UI dump completed (F10 / SparkingZeroAccess_dump.txt)
- UE5 built-in accessibility system: NOT available (compiled out)
- 688 TextBlocks, 487 RichTextBlocks — text is readable from widgets
- Game uses standard UMG widgets (TextBlock, Button, WidgetSwitcher, etc.)
- Game HUD: SSMainGameHUD, GameInstance: BP_SSGameInstance_C
- Key widget classes identified:
  - WBP_Title_C — title screen
  - WBP_Title_Button_C / WBP_Title_Button_PC_C — title buttons
  - WBP_Option_C — options menu
  - WBP_BTN_PauseMenu_C — pause menu buttons
  - WBP_Dialog_000_C / WBP_Dialog_002_C — dialogs
  - WBP_MainMenu_Base_TextSub_C — main menu text
  - WBP_OBJ_Option_List_* — option list items

## Phase 2: Menu Accessibility (IN PROGRESS)
- [x] Focus detection via HasKeyboardFocus() — works with both keyboard and controller
- [x] Title screen navigation (Start/Options/Quit) — labels spoken on focus change
- [x] Auto-dismiss dialog text reading (via RichTextBlock Text_Main_0, tracks text changes)
- [x] Main menu navigation — sub-button captions read via "caption" property
- [x] Main menu description text — TXT_GuideMessage queued after button label
- [x] Main menu tab suppression — WBP_MainMenu_Base_C / ModeMenu_C suppressed
- [x] Stage/BGM/Settings select — HitBtn_Text_XX mapped to BS_BTN_Menu_DP_XX captions
- [x] List header announcements — Text_Title tracked, announced on L1/R1 tab switch
- [x] SpeakQueued for non-interrupting speech (descriptions after labels)
- [x] Help window dismiss — queues "Press Back to close" after body text
- [x] List position announcements — "X of Y" for stage, BGM, and rule settings lists
- [x] Dialog button ordering — dialog header + body spoken before button label on open
- [x] Options menu setting names — Title/TitleText/TXT_Label read for setting labels (class-gated, no perf impact)
- [x] Options menu tips — TEXT_TipsMain read via FindAllOf (class-gated to Option_List widgets only)
- [x] Online: Room ID input — digit position, value, change announcements (cached refs for all 9 panels)
- [x] Key binding values — RichTextBlock caption inside ChangeKey child widgets
- [x] Icon markup parser — converts glyph tags to readable text (keys, PS/Xbox buttons)
- [x] Title screen "Press any button" — WBP_Title_C tracked in screen changes
- [x] Code split into modules — helpers, speech, widget_reader, poll_trackers, icon_parser
- [x] Character select: roster grid — character name + DP via texture ID lookup (rewritten 2026-03-29)
- [x] Character select: team slot numbers — "Slot 1" through "Slot 5" announced
- [x] Character select: skill slots — skill name with type prefix (Blast/Ultimate)
- [x] Character select: Switch/Remove/Switch View buttons via WidgetLabels
- [x] Character select: team slot character names — via IMG_Face_Main texture ID + lookup table
- [x] Character select: team slot DP values — calculated from static lookup table (208 chars)
- [x] Character select: character DP cost per slot — announced with character name
- [x] Character select: team overview guide bar — shortcuts announced on first entry
- [x] Character select: hold buttons (Start Battle, Return to Main Menu) — game-thread caption read
- [x] Skill list overlay — name, button combo, cost, description (skill_list.lua, works in roster + pause)
- [ ] Character select: costume/form selection within a character
- [x] Character select: 2P/CPU side team reading — R1 switches sides, full slot reading
- [ ] Character select: sort/filter overlay reading
- [ ] Character select: team presets reading
- [ ] Options: "Battle Assist" false title match on ControlButton
- [ ] Options: Language values shown as images, not text
- [ ] Options: Control style selector (full-screen overlay, no keyboard focus)
- [ ] Stage variant detection — arrow widgets identical for variant/no-variant stages
- [ ] HitBtn_Text_05 has no matching SetRuleBTN_05 on some settings screens
- [x] Pause menu navigation — WidgetLabels fast path, instant response
- [x] In-battle HUD — HP % thresholds (75/50/25/10), KI bars, Sparking activation/countdown
- [x] In-battle skill points — BlastStockCount changes announced
- [x] In-battle opponent tracking — all enemy pawns HP/KI/Sparking announced
- [x] In-battle enemy Sparking — activation, countdown, ended
- [x] Online: player pawn detection — camera controller + player side from team overview (see notes below)
- [x] In-battle match result screen — player level, rank up, rewards, win streak (polled via WBP_GRP_BS_Result_03_DP_C visibility)
- [ ] In-battle HP bar count — big number at bottom corners (remaining health bar layers, separate from HP %)
- [ ] In-battle transformation count — small number with up-arrow next to KI (available transformations for current character, CharaNum in StyleIcon_Timer)
- [x] Battle intro — skip shortcut announced
- [x] Title screen — "Loading" on logo, "Press confirm to start" with 1s delay
- [x] Icon parser — full PS/Xbox mappings, Triangle/Square fix, Left Stick vs D-Pad fix
- [x] In-battle timer — texture-based digit reading from WBP_Rep_TimerNum widgets, parent visibility check for hidden digits
- [x] Online: room settings labels read (Rank, Battle Rules, Time, etc.)
- [x] Online: Player Match room lobby — player panels with slot/name/status/wins
- [x] Online: room guide bar announced (Sub-menu, Show/Hide Room ID, Leave Room)
- [x] Online: room ID toggle detection — announces real ID when shown
- [x] Online: player status/join/leave polling in room lobby
- [x] Online: Sub-menu (Triangle) — Player Card, Training, Invite, Disband, Kick, etc.
- [x] Online: Rank Match lobby (basic navigation done; status changes after opponent joins still TODO)
- [x] Episode Battle: character select — character name (CaracterText_0), chapter title, story text, button captions (Continue/Story Map/New Game)
- [x] Episode Battle: character select guide bar — announced on first entry
- [x] Episode Battle: story map — saga/arc/chapter announced on entry with ~100ms delay (avoids Japanese placeholder text)
- [x] Episode Battle: story map node navigation — Text_EventTitle polled for changes, "???" filtered
- [x] Episode Battle: story map guide bar — Start, Back, Details, Recap, Change Difficulty, Episode Map
- [x] Episode Battle: path node detection — guide button count drop triggers "Path" + branch conditions
- [x] Episode Battle: branch conditions — visible WBP_OBJ_AI_BranchConditons_Set_C read with position + locked status
- [x] Episode Battle: cutscene skip — "Hold confirm to skip" announced when WBP_GRP_AI_EventSkip_C appears
- [x] Episode Battle: cutscene narration — RichText_MainTalk polled, only spoken when no Text_CharaName (voice-acted dialog skipped), "Press confirm to continue" icon queued after
- [x] Episode Battle: cutscene skip/next icons — raw icon markup passed through SpeakQueued for icon parser handling
- [x] Shop: top screen — Shop/Customize buttons via WidgetLabels
- [x] Shop: item grid — name + price for S-type (ability items) and L-type (characters/outfits/voices)
- [x] Shop: item descriptions — queued after item, filtered for duplicates and useless fragments
- [x] Shop: category tabs — announced on first entry and polled for L1/R1 changes
- [x] Shop: Zeni balance — announced on first entry
- [x] Shop: purchase dialog — header, item, price, balance after, button label (tracks header for dedup)
- [x] Shop: purchase complete dialog — detected via header text change
- [ ] Shop: page navigation — pager items visible but not yet announced
- [ ] Shop: customize screen — not yet explored
- [ ] Episode Battle: consecutive path nodes — no signal to detect movement between adjacent path nodes (no text/widget changes)
- [ ] Episode Battle: story map "Close" (Square) toggle — outline panel visibility toggle, not yet handled
- [ ] PS4 icon table — separate from PS5, only Pad_05=Cross mapped so far. More mappings needed as discovered
- [ ] skill_list.lua line 117 — `table.insert` crash: "bad argument #2 (number expected, got string)". Pre-existing bug, investigate next session
- [ ] In-battle victory screen — removed (too many false triggers from intro dialogue TextWindow; player knows win/loss from gameplay)
- [ ] Character select: locked character detection — lock is purely visual (icon overlay), no text signal. Need to probe CharaIcon widget properties

### Online Player Pawn Detection — SOLVED (2026-04-05)
**Problem:** When player 2 (invited player), own HP/KI announced as "Enemy" and opponent's as own.
**Root cause:** In online matches, 3 BP_BattlePlayerController_C instances exist. Both active pawns have different controllers but both claim `IsLocalController()=true`. `IsLocallyViewed()` works for P2 but inverts for P1. The camera controller's Pawn is always the P1-side character.
**Solution:** Two-part approach:
1. **Player side detection:** Team overview sets `_playerSide` ("1P" or "2P") on first focus entry. Only the first value is accepted (browsing opponent's team won't overwrite). Reset when re-entering character select from a non-team screen.
2. **Pawn identification:** Find the controller whose `GetViewTarget()` is `BP_DirectorMainCamera_C` — its `.Pawn` is always the P1-side character. If we're P1, use that pawn. If we're P2, use that pawn's `TargetPawn` (our character from P1's perspective).
**Key findings from debug dumps:**
- Camera controller (GetViewTarget=BP_DirectorMainCamera_C) always has Player=LocalPlayer_2147481445 (consistent ID)
- Its Pawn = P1-side character always
- The other local controller's Pawn = P2-side character, with GetViewTarget pointing to its own pawn
- `IsLocallyViewed()` = true on P2-side pawn, false on P1-side pawn (unreliable for identification alone)
- Fallback to FindFirstOf controller approach for offline/single player

### Team Slot Character Name — SOLVED (2026-03-29)
**Solution:** Read character portrait texture from IMG_Face_Main Image widget inside each
CharaIcon via Brush.ResourceObject.GetFullName(). Texture names encode character IDs
(e.g. T_UI_ChThumbP1_0000_00_00 = Goku Z-Early). Lookup table maps IDs to display names.
Source: community Google Sheet, auto-updated via `uv run scripts/Update-CharaNames.py`.

**Key discoveries:**
- Text_CharaName in speech bubble contains placeholder text "キャラ名はここ", not actual name
- UE4SS Blueprint property access returns opaque UObject pointers (false positives)
- FSlateBrush.ResourceObject.GetFullName() works from LoopAsync (unlike TextBlock text reading)
- SSCharacterDataAsset (294 instances) uses same ID scheme as textures
- SetText hook registered but never fired (game doesn't use SetText for bubble text)
- ExecuteInGameThread didn't fix TextBlock reading either

### Focus Detection Architecture
- **IsValidRef():** Uses UE4SS IsValid() API to check UObject liveness before accessing cached refs. Only used on cached/persisted references, NOT on FindAllOf iteration results (too expensive).
- **Fast path:** Check cached widget reference with IsValidRef + HasKeyboardFocus() — 2 calls, instant
- **Slow path:** Single FindAllOf("UserWidget"), iterate checking HasKeyboardFocus() with pcall per-widget
- **Poll rate:** 16ms (LoopAsync), feels instant on fast path
- **Transition safety:** Dialog-dismiss cooldown (400ms) + RegisterLoadMapPostHook for map transitions + watchdog restarts dead loops
- **Widget dedup:** Checks both widget name AND object identity (handles duplicate names across team/roster)

### UE4SS API Discoveries (v3.0.1)
**APIs we adopted:**
- `IsValid()` — UObject liveness check. Used on cached refs only (too expensive for iteration). Falls back to pcall(GetFullName) if IsValid not available.
- `FindFirstOf(className)` — Returns first non-CDO instance. Used for singleton lookups (ReadGuideMessage, ReadOptionsTip, PollScreenChanges).
- `RegisterLoadMapPostHook(callback)` — Fires after map loads. Used to reset all state on map transitions instead of fragile dialog-dismiss heuristics.

**APIs available but not yet used:**
- `RegisterHook("/Script/UMG.UserWidget:Construct/Destruct")` — Widget lifecycle hooks. Too noisy for focus tracking but could help detect screen changes.
- `NotifyOnNewObject(className, callback)` — Widget creation detection. Could replace FindAllOf for screen detection.
- `ExecuteInGameThread(callback)` — Queue code on game thread. May fix the bubble TextBlock reading issue (threading context).
- `ExecuteWithDelay(delayMs, callback)` — One-shot delayed execution. Could replace frame-counting approaches.
- `RegisterHook` on game-specific UFunctions — Could capture character selection events if we find the right functions.

**APIs investigated but not useful:**
- `RegisterHook on OnFocusReceived` — Only fires if game widgets override the Blueprint event (most don't)
- UObject property access on Blueprint types — Returns opaque pointers for most game-specific properties. UE4SS reflection can't resolve Blueprint-defined structs.

### Dialog Detection
- Polls at 100ms (dialogs don't use focus, auto-dismiss)
- Tracks both visibility AND text content per dialog instance
- Text found in RichTextBlock named Text_Main_0 inside WBP_Dialog_000_C
- Dialog button captions in RichTextBlock named "caption" inside button sub-widgets
- Dialog dismiss triggers 400ms transition cooldown

### Widget Naming
- Live instances in "/Engine/Transient..." paths, blueprint defaults in "/Game/SS/UI/..." paths
- Button names from widget tree: StartButton, OptionButton, QuitButton, StoreButton
- WidgetLabels table maps internal names to spoken labels
- HitBtn_Text_XX pattern: focus lands on transparent hit areas, actual labels in sibling BS_BTN_Menu_DP_XX caption TextBlocks (same suffix number)
- Fallback: GetButtonText reads child TextBlock/RichTextBlock, then CleanWidgetName
- SuppressedClasses table prevents container widgets from being announced

### Main Menu Structure
- WBP_MainMenu_Base_C — main frame (suppressed)
- WBP_MainMenu_ModeMenu_C — tab content container (suppressed)
- 6 tabs cycled with L1/R1 (tab names are images, not text — cannot be read)
- Sub-buttons: WBP_OBJ_MainMenu_BTN_Sub1_C with "caption" property
- TXT_GuideMessage — description text that changes per selection
- Character speech bubble: RichText_MainTalk + Text_CharaName

### Character Select Structure
- **Team overview:** WBP_GRP_BS_Top_00_1P_C / _2P_C with HitButton_0 through _4 (team slots)
- **Roster grid:** WBP_GRP_BS_CharaList_DP_C with HitButton_00 through _33+ (character grid)
- **Info panel:** WBP_GRP_BS_CharaNameSet_DP_C — Text_Name, Text_Name_Plus, Text_CharaBonusNum
- **Skills panel:** WBP_GRP_BS_SkillList_DP_C — SkillBTN_0/1 (normal), SkillBTN_Brast_0/1 (blast), SkillBTN_Ult_0 (ultimate)
- **Speech bubble:** WBP_OBJ_Common_TexWin_Black — Text_CharaName (only with 2+ team members)
- **Character icons:** WBP_OBJ_BS_CharaIcon_00_C — properties all opaque UObjects
- **Action buttons:** HitBTN_Replace (Switch), HitBTN_Remove (Remove), Toggle_HitButton (Switch View)

### Shop Structure (2026-04-04)
- **Module:** shop.lua — item grid, categories, purchase dialogs
- **Top screen:** WBP_GRP_SH_Top_C
  - WBP_OBJ_SH_BTN_Shop_C / WBP_OBJ_SH_BTN_Customize_C — via WidgetLabels
- **Main panel:** WBP_GRP_SH_Main_00_C
  - TXT_ShopName, TXT_CategoryName, TXT_Detail_00 (description), TXT_Money (Zeni balance)
  - TXT_Shortage_Guide_0/1 — static labels, NOT per-item (cannot detect sold-out)
  - WBP_OBJ_SH_Custom: Text_00-04 — stat labels (HP, Attack, Ki, Agility, Special Attack)
- **Item grids:**
  - S-type (small, ability items): WBP_GRP_SH_Main_S00_C → WBP_OBJ_SH_ItemIcon_S00_C through S19
  - L-type (large, characters/outfits/voices): WBP_GRP_SH_Main_L00_C → WBP_OBJ_SH_ItemIcon_L00_C through L15
  - Each item has TWO TextBlock layers: template + real data. Template has Japanese placeholders and "99,999,999,000" price. Use FIRST non-template match.
  - L-type grids persist across category switches — must match on widget FULL PATH (after `:`) not just name
  - Child widgets inside item icons receive focus after the icon itself — generic handler dedup needed
  - TXT_Detail_00 contains item name (not description) for Outfits; "Emote Voiceover Set of" for Voices — filtered
- **Categories:** WBP_OBJ_SH_BTN_Category_00 through _06, L/R buttons
  - TXT_CategoryName polled for changes (focus doesn't change on L1/R1)
- **Pages:** WBP_OBJ_SH_Pager_Item_1 through _5
- **Purchase dialog:** WBP_Dialog_SH_000_C (reused instance)
  - Txt_Header ("Purchase the following items?" / "Purchase complete.")
  - TXT_ItemLabel, TXT_Price, TXT_Money_0 (before), TXT_Money_1 (after)
  - TXT_ItemNum ("Held"), TXT_ItemNum_0 (count owned)
  - Buttons: LeftButton (OK), RightButton (Purchase/Cancel) — WBP_OBJ_Dialog_Button_C
  - Dialog pattern `WBP_Dialog_%d+_C_%d+` does NOT match shop dialogs (Lua `%w` excludes underscore)
  - Dedup via header text comparison (same header = switching buttons, different = new dialog)

### Episode Battle Structure (2026-04-04)
- **Module:** episode_battle.lua — character select, story map, cutscene skip
- **Container:** WBP_GRP_AI_CharacterSelect_C (suppressed in widget_reader)
- **Character select:**
  - 6 character panels: WBP_OBJ_AI_CharacterPanel_0-5 with Text_CharacterName_1
  - Focus on WBP_OBJ_Common_HitButton_C (no text) — both chars and action buttons
  - Selected character: CaracterText_0 (note game typo "Caracter")
  - Action buttons: WBP_OBJ_AI_BTN_Menu_0 (New Game), _1 (Continue), _2 (Story Map) — caption TextBlocks
  - HitButton suffix maps to BTN_Menu suffix for button reading
  - Outline panel: TXT_ChapterTitle ("Previously..." or "Character Introduction") + TXT_main (story/bio)
  - Characters with progress: 2 HitButtons + 2-3 BTN_Menu. Without: 1 HitButton + 1 BTN_Menu
- **Story map:**
  - WBP_GRP_AI_ChartTitle_C — detected via Text_ScenarioTitle_0 (not FindFirstOf, avoids crash)
  - Text_ScenarioTitle_0 (saga), Text_ScenarioTitle_1 (arc), Text_Chapter, Text_EventTitle (node title)
  - "???" in Text_EventTitle = placeholder, filtered out
  - No keyboard focus on map nodes — poll-based text change detection
  - Path nodes: guide button count drops (<=3), Text_EventTitle unchanged
  - WBP_OBJ_AI_BranchConditons_Set_C: Text_BranchCondition_0/1/2 — branch requirements
  - Branch conditions: use IsVisible() on parent widget to filter, but many stay visible across map
  - Entry announcement delayed ~100ms to avoid reading char select's stale guide bar / Japanese placeholders
- **Cutscene:** WBP_GRP_AI_EventSkip_C with hold button "Skip" — FindFirstOf guarded by _announcedEntry flag
- **Cutscene dialog:** WBP_GRP_Common_EventText_C > WBP_OBJ_Common_TextWindow with Text_CharaName + RichText_MainTalk (not yet implemented, voice acted)

### Stage/BGM/Settings Select
- WBP_GRP_BS_StageList_DP2_C — list container with Text_Title header ("Stage", etc.)
- WBP_OBJ_Common_HitBtn_Text_XX — transparent hit areas that receive focus
- WBP_OBJ_BS_BTN_Menu_DP_XX — actual menu items with caption TextBlocks
- Same suffix number links focus widget to label widget
- L1/R1 cycles between views, header announced via Text_Title tracking

### Battle HUD — Game State Properties (2026-03-29)
**On SSCharacter (C++ class, readable via pawn.PropertyName):**
- `HPGaugeValue` (FloatProperty, 0x2A14) — current HP, percentage-based thresholds used
- `SPGaugeValue` (FloatProperty, 0x2A18) — KI energy, 10k per bar, max 50k (5 bars)
- `SparkingGaugeValue` (FloatProperty, 0x2A30) — Sparking gauge, full = 50k
- `BlastStockCount` (IntProperty, 0x2A48) — blast stock count
- `ComboNum` (IntProperty, 0x2B24) — current combo hit count
- `BattleState` (EnumProperty) — character state

**On BP_BattleGameStateBase_C:**
- `ReplicatedWorldTimeSeconds` (FloatProperty) — elapsed world time
- `bIsTimeOverSettle` (BoolProperty) — time-over flag
- Match countdown timer NOT directly exposed as a property

**Player pawn access:** Camera controller (GetViewTarget=BP_DirectorMainCamera_C) + player side from team overview. See "Online Player Pawn Detection" notes.
**Opponent detection:** Player pawn's TargetPawn property, or all BPCHR_ pawns except player's

### Post-Battle Result Screen (2026-04-06)
**Detection:** Poll for `WBP_GRP_BS_Result_03_DP_C` visibility (FindAllOf, not FindFirstOf). Wait for rewards to populate (non-placeholder) before announcing.
**Widgets and TextBlocks:**
- `WBP_GRP_BS_Result_03_DP_C` — result panel (scoped by instance ID for Text_RankNum)
  - `Text_RankNum` — player level number
  - `Text_UserName` — your username
  - `Text_Rank` — "Player Level" label
- `WBP_GRP_BS_PlayerRankUP_C` — rank up panel (only visible when you rank up; hidden = Japanese placeholder)
  - `Text_RewardInfo` — "Rank Up"
  - `Text_RankNum_0` — new level number
- `WBP_GRP_MainMenu_Notification_gift_C` → `WBP_OBJ_MainMenu_Notification_gift_Item_X`
  - `Txt_ItemName` — reward name (filter "アイテム名" placeholder)
  - `TXT_Num` — amount (filter "99999999" placeholder)
  - `Txt_Header` — "New Rewards"
- `WBP_PlayerInfo_C` (not always present in online)
  - `Txt_WinningStreak_Value` — your win streak (filter "999" placeholder)
**Timing:** Result panel appears ~10s after battle ends. Rewards populate ~5s after panel. Rank up ~7s after. Code retries every 100ms until rewards are real.

### Title Screen Flow
1. Auto-dismiss dialog 1 (autosave notice)
2. Auto-dismiss dialog 2 ("Loading saved data...")
3. "Press any button" screen (WBP_Title_PressAnyButton_C)
4. Collapsed title: Start + Quit (WBP_Title_Button_PC_C: GameStart_Button, GameQuit_Button)
5. Expanded title: Start + Options + Quit (WBP_Title_Button_C: StartButton, OptionButton, QuitButton)
6. Start → Main menu

## Known Issues
- UniversalSpeech reports "JAWS" as detected engine even when NVDA is active (cosmetic, speech works correctly through NVDA)
- UE4SS GUI debug window disabled (GuiConsoleVisible=0) for accessibility
- Team slot character names not readable (see investigation notes above)
- Crash dumps generated frequently by the game (pre-existing, not mod-related) — `crash_*.dmp` in Win64 directory

## Architecture
- UE4SS Lua mod: SparkingZeroAccess (Mods/SparkingZeroAccess/Scripts/)
  - main.lua — orchestrator: focus tracking, keybinds, init, RegisterLoadMapPostHook
  - helpers.lua — TryCall, TryGetProperty, GetWidgetName, GetClassName, IsValidRef
  - speech.lua — speech init, Speak/SpeakQueued (applies icon_parser automatically)
  - widget_reader.lua — text reading, widget matching, label resolution, list position
  - poll_trackers.lua — dialog, help window, screen change, room ID/status polling
  - icon_parser.lua — converts RichText icon markup to readable text (full PS/Xbox/keyboard mappings)
  - skill_list.lua — Explanation of Controls overlay: skill name, button combo, cost, description
  - episode_battle.lua — Episode Battle (story mode): char select, story map, cutscene skip
  - shop.lua — Shop: item grid (S/L types), categories, purchase dialogs, Zeni balance
  - battle.lua — battle HUD: HP/KI/Sparking announcements, opponent tracking, intro skip
  - team_overview.lua — team setup screen: slot navigation, bubble name reading
  - chara_roster.lua — character roster grid: name reading, skills, teamlist (cached TextBlock refs)
  - debug_tools.lua (F4-F8, loaded via require, remove to disable)
- Speech bridge: speech_bridge.dll (Lua C module, statically links Lua 5.4, dynamically loads UniversalSpeech.dll)
- Speech library: UniversalSpeech.dll (pre-built 64-bit, supports NVDA/JAWS/SAPI fallback)
- Build artifacts in: D:\games\DRAGON BALL Sparking! ZERO mod\build\
- GCC compiler: WinLibs MinGW-w64 (installed via winget)
- Build command (run from `build/` directory): `gcc -shared -o speech_bridge.dll speech_bridge.c lua-5.4.7/src/liblua54.a -luser32`
- Git repo initialized at mod directory (branch: main)

## Files Modified in Game Directory
- SparkingZERO\Binaries\Win64\UE4SS-settings.ini (bUseUObjectArrayCache, GraphicsAPI, GuiConsoleVisible)
- SparkingZERO\Binaries\Win64\Mods\mods.txt (added SparkingZeroAccess)
- SparkingZERO\Binaries\Win64\Mods\SparkingZeroAccess\ (our mod)
- SparkingZERO\Binaries\Win64\UniversalSpeech.dll, nvdaControllerClient.dll, ZDSRAPI.dll
