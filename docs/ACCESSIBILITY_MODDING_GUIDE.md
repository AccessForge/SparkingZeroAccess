# Accessibility Modding Guide for Screen Reader Users

A guide for creating game accessibility mods that enable blind players to play using screen readers (NVDA, JAWS, etc.).

## Core Accessibility Goals

### Core Principle: Playability, Not Simplification

**The goal is to make the game playable for blind players in the same way sighted players experience it.** Accessibility means equal access to the gameplay - not a simplified version.

- **No cheats without asking:** Only suggest cheats or simplifications when there is absolutely no other way to make a game mechanic accessible.
- **Never add automatically:** Never implement cheats or shortcuts without explicitly asking first.
- **Full game experience:** All game mechanics, challenges, and decisions should be preserved.

### Technical Goals

- Well-structured text output (no tables, no graphics)
- Linear, readable format for screen readers
- Use a screen reader communication library (e.g., Tolk for NVDA/JAWS on Windows)
- Full keyboard navigation support

## Screen Reader Communication Principles

### What to Announce
- Context changes (screen transitions, mode changes, phase changes)
- Currently focused elements
- Game state updates (health, resources, turn information)
- Available actions and their results
- Error states and confirmations

### How to Announce
- Output plain text optimized for screen readers
- Keep announcements concise but informative
- Provide detailed information in navigable blocks (arrow key navigation)
- Allow users to repeat the last announcement (e.g., Ctrl+R)
- Announce automatically on important events, but avoid spam

### Announcement Patterns

Use consistent formats for different announcement types:

**Menu/List Navigation:**
```
[MenuName], [Position] of [Total]: [ElementName]
Example: "Inventory, 3 of 12: Health Potion"
```

**Status Changes:**
```
[What] [Direction] [Value] (optional: [Context])
Example: "Health dropped to 45 of 100"
```

**Action Confirmation:**
```
[Action] [Object] (optional: [Result])
Example: "Used Health Potion, health full"
```

**Errors/Warnings:**
```
[Warning/Error]: [Reason]
Example: "Cannot do that: Inventory full"
```

### Queued vs. Interrupting Announcements

**Interrupting (Standard):** Stops previous speech, speaks immediately
**Queued:** Waits until previous speech finishes

Use queued for additional info after a main announcement. Tolk's `Tolk_Output(text, interrupt)` supports this directly - passing `false` for the interrupt parameter queues the message:

```csharp
// Main message (interrupts previous speech)
ScreenReader.Say("Quest accepted: Find the lost artifact");

// Additional info (queued - waits for previous speech to finish)
ScreenReader.Say("Press J to open quest log", false);
```

**When to use queued (interrupt = false):**
- Available key commands after panel opening
- Response options after dialog text
- Hints after action confirmation

### Announcement Priority (Suggestion)

When multiple events happen at once (e.g., combat + status change + popup), you need to decide what the user hears first. This is highly game-specific - there is no universal rule. Consider these rough guidelines and adapt to each game:

**Higher priority (typically interrupt):**
- Critical state changes (health critical, game over, death)
- Screen/mode transitions (menu opened, battle started)
- Dialog text and response options
- Error messages ("Can't do that")

**Lower priority (typically queued):**
- Navigation announcements (item selection)
- Status updates (resource counts)
- Hints and tooltips
- Available key commands after panel opening

**Simple implementation:** For most mods, using `ScreenReader.Say(text)` for important things (interrupts previous speech) and `ScreenReader.SayQueued(text)` for additional info (waits) is sufficient. Only build a full priority queue system if you have a game with many simultaneous events (e.g., real-time combat with UI overlays).

**When in doubt:** Test with a screen reader and listen. If important information gets drowned out by less important announcements, increase priority of the important one. If the user misses context because everything interrupts, use more queuing.

## Output Formatting for Screen Readers

### Avoid
- Tables (pipe | symbols are read aloud character by character)
- ASCII art or graphical representations
- Relying on spatial positioning to convey meaning
- Multiple columns of information

### Prefer
- Headings and bullet lists for structure
- Linear, one item per line presentation
- Group related info under clear labels
- Consistent ordering of information

### Example Format
Instead of tables, format information like this:

**Item Name**
- Property: Value
- Property: Value
- Property: Value

**Another Item**
- Property: Value
- Property: Value

## Keyboard Navigation Design

### Reserved Keys (Do NOT Override)
- Tab - Standard UI navigation
- Enter - Confirm/activate
- Escape - Cancel/back

### Recommended Key Patterns
- Arrow keys for navigation within a focused area
- F1 for help, F2 for context information
- Space for primary action/confirm
- Function keys for global actions

### Context-Aware Keys
- Keys can have different functions based on game state
- Always announce what the current context allows
- Provide audio feedback for mode/context changes

### Modifier Keys for Bulk Actions

For buy/sell or other quantity actions:

```csharp
private int GetQuantityMultiplier()
{
    if (Input.GetKey(KeyCode.LeftAlt)) return 100;
    if (Input.GetKey(KeyCode.LeftControl)) return 10;
    if (Input.GetKey(KeyCode.LeftShift)) return 5;
    return 1;
}

// Announce when panel opens:
// "Hold Shift for 5, Ctrl for 10, Alt for 100 units."
```

## Advanced: Central Announcement Manager (optional)

For most mods, calling `ScreenReader.Say()` directly from handlers works fine. However, for games with many simultaneous events, consider an AnnouncementManager that sits between handlers and ScreenReader:

```
Handler → AnnouncementManager → ScreenReader → Tolk → Screen Reader
```

### When You Might Need This

- **Real-time strategy games:** Multiple units reporting status, buildings completing, resources changing - all at once
- **Action RPGs with busy UI:** Combat log + health changes + buff/debuff notifications + loot drops simultaneously
- **Games with multiple overlapping panels:** Chat messages arriving while navigating inventory while a quest notification pops up

### What It Could Do

- **Priority filtering:** Critical messages (health critical, game over) always interrupt. Low-priority messages (ambient hints) only speak when nothing else is queued.
- **Duplicate suppression:** If "Health: 45" is already queued, don't queue it again.
- **Verbosity control:** Reduce detail level when many events are competing. Full detail when things are calm.
- **Rate limiting:** In a rapid combat log, summarize instead of reading every line ("3 enemies defeated" instead of announcing each one).

### Why NOT to Use This by Default

- Adds complexity that most mods don't need
- Harder to debug (messages go through an extra layer)
- Turn-based games, menu-heavy games, and most indie games don't have enough simultaneous events to justify it
- Simple `Say()` (interrupt) and `SayQueued()` (queue) cover 90% of cases

**Recommendation:** Start without an AnnouncementManager. If you find that important messages are getting lost in a flood of less important ones, that's the signal to introduce one. The Announcement Priority section above gives simpler alternatives to try first.

---

## Code Architecture Recommendations

### Quellcode-Recherche vor der Implementierung

**KRITISCH: Niemals raten, immer verifizieren!**

Bevor du einen neuen Handler schreibst, eine Spielmechanik ansprichst oder UI-Elemente referenzierst, MUSST du den dekompilierten Quellcode im `decompiled/` Ordner durchsuchen. Das Erraten von Klassennamen, Methodennamen oder Spielmechaniken führt unweigerlich zu Fehlern.

#### Warum ist das so wichtig?

- Spiele verwenden oft unerwartete Namenskonventionen (z.B. `CardZone` statt `Hand`, `UIManager` statt `GameUI`)
- Interne Mechaniken funktionieren selten so, wie man es von außen vermutet
- Falsche Annahmen führen zu Code, der kompiliert aber nicht funktioniert - schwer zu debuggen
- Reflection auf nicht-existente Felder schlägt still fehl

#### Was muss VOR jeder Implementierung geprüft werden?

**Bei neuen Handlern:**
- Wie heißt die UI-Klasse/das Panel genau? (`decompiled/` durchsuchen)
- Welche Methoden hat sie? (IsOpen, Show, Hide, etc.)
- Wie ist die Hierarchie aufgebaut? (Parent-Child-Beziehungen)
- Welche Events/Callbacks existieren?

**Bei Spielmechaniken:**
- Wie heißen die relevanten Klassen? (z.B. `InventoryManager`, `PlayerInventory`, `ItemStorage`?)
- Welche Properties/Felder sind öffentlich zugänglich?
- Gibt es Singleton-Instanzen? Wie greift man darauf zu?
- Welche Methoden ändern den Zustand?

**Bei UI-Elementen:**
- Exakte Namen der GameObjects/Panels
- Komponententypen (Text, TextMeshProUGUI, Button, etc.)
- Verschachtelung und Pfade in der Hierarchie

**Bei Tasteneingaben:**
- Wie verarbeitet das Spiel Input? (Unity Input, InputSystem, Custom?)
- Welche Tasten sind bereits belegt?
- Gibt es InputBlocker oder Fokus-Systeme?

#### Typische Suchmuster im dekompilierten Code

```
Grep-Pattern für UI-Screens:
- "class.*Menu" oder "class.*Screen" oder "class.*Panel"
- "public static.*Instance" (für Singletons)
- "void Show" oder "void Open" oder "void Display"

Grep-Pattern für Spielmechaniken:
- "class.*Manager" oder "class.*Controller"
- "public.*List<" oder "public.*Dictionary<" (für Sammlungen)
- "static.*Current" oder "static.*Active" (für aktiven Zustand)

Grep-Pattern für spezifische Features:
- Suche nach dem englischen Begriff der Mechanik
- Suche nach UI-Text, der im Spiel sichtbar ist
- Suche nach Variablennamen, die logisch erscheinen
```

#### Checkliste vor der Implementierung

Bevor du Code schreibst, stelle sicher:

- [ ] Relevante Klassen im `decompiled/` Ordner gefunden
- [ ] Exakte Klassennamen notiert (Groß-/Kleinschreibung!)
- [ ] Zugriffsmethode verstanden (Singleton? FindObjectOfType? Referenz?)
- [ ] Öffentliche API der Klasse bekannt (Methoden, Properties)
- [ ] Erkenntnisse in `docs/game-api.md` dokumentiert

#### Beispiel: Falsches vs. Richtiges Vorgehen

**FALSCH (Raten):**
```csharp
// "Das Inventar heißt bestimmt InventoryPanel..."
var inventory = GameObject.Find("InventoryPanel");
// Funktioniert nicht - heißt in Wirklichkeit "UI_Inventory_Main"
```

**RICHTIG (Recherchieren):**
```
1. Grep im decompiled/ Ordner: "Inventory"
2. Finde: class UI_Inventory_Main : MonoBehaviour
3. Prüfe: Hat static Instance Property? Ja!
4. Code: var inventory = UI_Inventory_Main.Instance;
```

#### Wann erneut recherchieren?

- Bei JEDEM neuen Handler
- Bei JEDER neuen Spielmechanik
- Wenn Code unerwartet nicht funktioniert
- Wenn Reflection fehlschlägt
- Nach Spiel-Updates (Namen können sich ändern)

### Core Principles
- **Modular** - Separate concerns: input handling, UI extraction, announcement, game state
- **Maintainable** - Clear structure, consistent patterns, easy to extend and debug
- **Efficient** - Avoid unnecessary processing, minimize performance impact on the game. Cache object *references* only — always read *values* live. Never silently fall back to stale cached data
- **Game-Integrated** - Always use original game methods for actions; never bypass game logic

### Essential Utility Classes to Build
- **UITextExtractor** - Extract readable text from UI elements
- **ElementActivator** - Programmatically activate/click UI elements
- **ElementDetector** - Identify element types (cards, buttons, etc.)
- **AnnouncementManager** - Queue and deliver screen reader output
- **KeyboardHandler** - Central input processing with context awareness

### Code Standards
- Avoid redundancy - reuse code, don't duplicate logic
- Consistent naming conventions throughout the project
- **IMMER `decompiled/` durchsuchen vor der Implementierung** (siehe Abschnitt oben)
- Always use your utility classes instead of duplicating logic
- Handle edge cases gracefully (missing elements, unexpected states)

### Handler Architecture

**Keep your main file small.** Create separate handler classes for each screen/feature.

**Each handler should have:**
- `IsOpen()` - Static method to check if this UI is active
- `Update()` - Called every frame, tracks state changes
- `OnOpen()` / `OnClose()` - Called when UI opens/closes
- `Navigate(direction)` - Handle arrow key navigation
- `AnnounceStatus()` - Announce current state (for F-key shortcuts)

**Handler registration in main:**
```csharp
// 1. Declare field
private InventoryHandler _inventoryHandler;

// 2. Initialize
_inventoryHandler = new InventoryHandler();

// 3. Update each frame
_inventoryHandler.Update();

// 4. F-key dispatch
if (Input.GetKeyDown(KeyCode.F2))
    _inventoryHandler.AnnounceStatus();
```

**Rule of thumb:** One handler per screen/feature. Split when a handler exceeds 200-300 lines.

**For 3+ handlers sharing keys (Enter, Escape, arrows):** Use `AccessStateManager` to coordinate which handler is active. See `templates/shared/AccessStateManager.cs.template` for the full implementation with Context tracking, events, and Escape handling. See `docs/state-management-guide.md` for details.

### State Change Detection

Only announce on actual changes - not every frame:

```csharp
public class NavigationHandler
{
    private string _lastAnnouncedLocation;
    private string _lastAnnouncedTarget;

    public void Update()
    {
        var currentLocation = GetCurrentLocation();
        if (currentLocation != _lastAnnouncedLocation)
        {
            _lastAnnouncedLocation = currentLocation;
            ScreenReader.Say($"Entered {currentLocation}");
        }

        var currentTarget = GetCurrentTarget();
        if (currentTarget != _lastAnnouncedTarget)
        {
            _lastAnnouncedTarget = currentTarget;
            if (!string.IsNullOrEmpty(currentTarget))
                ScreenReader.Say($"Target: {currentTarget}");
        }
    }
}
```

### Performance: Per-Frame Polling (Update Loops)

A common question: Is it okay to check things every frame? **Yes — as long as you're careful about what you do per frame.**

Unity's `Update()` runs every frame (typically 60+ times per second). The game itself does far more expensive work per frame (rendering, physics, AI) than anything our mod checks. A few lightweight comparisons per frame are completely negligible.

#### What costs virtually nothing per frame

These operations are so cheap that running them every frame is perfectly fine:

- `Input.GetKeyDown()` — this is exactly how Unity expects input to be handled
- Comparing a bool, int, or float (`currentHealth != _lastHealth`)
- Null checks (`if (panel == null)`)
- Checking a cached reference's property (`_panel.activeInHierarchy`)

Even 10+ handlers doing these kinds of checks simultaneously are unmeasurable compared to what the game does per frame.

#### What should NOT happen every frame

These operations are expensive and should only run when a change is detected or on a timer:

- `GameObject.Find()` or `FindObjectOfType()` — searches the entire scene hierarchy
- Reflection calls (`GetField()`, `GetValue()`) — slow method lookup and invocation
- String building/concatenation — allocates memory, creates garbage collection pressure
- `ScreenReader.Say()` / Tolk output — a screen reader can't process 60 messages per second anyway
- `GetComponentsInChildren()` — traverses the hierarchy every call

#### The correct pattern: Check per frame, act only on change

```csharp
private float _lastHealth;

void Update()
{
    // Cheap: one float comparison per frame
    float currentHealth = player.health;
    if (currentHealth != _lastHealth)
    {
        // Expensive work only when something actually changed
        _lastHealth = currentHealth;
        ScreenReader.Say(Loc.Get("health_changed", currentHealth));
    }
}
```

#### Caching: References only, never values

Cache **object references** (the GameObject itself) to avoid expensive lookups every frame. But always read **values** (text, health, item counts) live from the source — never cache and return stale values.

**Why this matters for accessibility:** A sighted player sees when the screen updates. A blind player trusts whatever the screen reader says. If you show a cached value when the live lookup fails, the player gets wrong information with no way to notice. This is silent degradation — the worst outcome for an accessibility mod.

```csharp
// BAD: Searches the scene every frame
void Update() {
    var panel = GameObject.Find("InventoryPanel"); // Slow!
}

// GOOD: Cache the reference, re-find if lost, LOG if re-find fails
private GameObject _cachedPanel;
void Update() {
    if (_cachedPanel == null)
    {
        _cachedPanel = GameObject.Find("InventoryPanel");
        if (_cachedPanel == null)
        {
            DebugLogger.Log("InventoryPanel not found");
            return; // Don't silently use old data
        }
    }
}

// BAD: Caching a value and returning it as fallback
private string _lastItemName;
string GetItemName() {
    var name = GetLiveItemName();
    if (name != null) _lastItemName = name;
    return _lastItemName; // Silent degradation!
}

// GOOD: Live read, explicit failure
string GetItemName() {
    var name = GetLiveItemName();
    if (name == null)
    {
        DebugLogger.Log("Could not read item name");
        ScreenReader.Say("Item not readable");
        return null;
    }
    return name;
}
```

#### Throttling: For moderately expensive checks

When you need to do something more expensive than a simple comparison (e.g., iterating a list of items to detect changes), but there are no events to hook into:

```csharp
private float _lastCheck;
private const float CHECK_INTERVAL = 0.1f; // 10 times per second is plenty

void Update() {
    if (Time.time - _lastCheck < CHECK_INTERVAL)
        return;
    _lastCheck = Time.time;

    // Moderately expensive checks here (list iteration, multiple property reads)
}
```

10 times per second is fast enough that the user won't notice any delay, but reduces work by 80-85% compared to every-frame checking.

#### When per-frame checks are necessary

- **Input handling** — `GetKeyDown` must be checked every frame or key presses are missed
- **State change detection without events** — when the game doesn't fire events for something (e.g., no OnHealthChanged event), polling is the only option
- **UI focus tracking** — when the game doesn't fire selection events, you must check which element is highlighted each frame

#### When to use Harmony patches instead of polling

If the game has clear methods that are called when things happen, hook them with Harmony instead of polling:

- `OnMenuOpen()`, `OnMenuClose()` — patch these instead of checking `isOpen` every frame
- `OnItemSelected()`, `OnSelectionChanged()` — patch instead of tracking selection index
- `TakeDamage()`, `Heal()` — patch instead of comparing health values

**Rule of thumb:** Use Harmony patches when the game has hookable methods. Use per-frame polling when it doesn't. Both are legitimate — the game's architecture determines which is appropriate.

**Note:** The examples use Unity API. For other engines, apply the same principles with equivalent APIs.

### Game Integration

**Always use original game methods for actions.** When the mod performs actions like picking up items, buying, or interacting - use the game's own methods, not direct manipulation.

**Why this matters:**
- Game tracks statistics, achievements, progress
- Sound effects and visual feedback play correctly
- Other game systems get notified (quests, tutorials, etc.)
- Prevents desyncs and broken game states

```csharp
// BAD: Bypasses game logic - achievements/sounds/stats won't trigger
player.inventory.items.Add(item);
itemOnGround.SetActive(false);

// GOOD: Uses game's pickup method - all systems get notified
player.PickupItem(item);

// BAD: Direct gold manipulation
player.gold += 100;

// GOOD: Game handles it properly
shop.SellItem(item); // Triggers sound, updates UI, logs transaction
```

**Rule of thumb:** If the game has a method for an action, use it. Only manipulate data directly when there's no alternative.

## Error Handling

### Rules

1. **Null-safety with logging:** Never fail silently. If something is null, log via DebugLogger AND tell the user something useful via ScreenReader.
2. **Try-catch ONLY where failures are expected:** Reflection access (field names may change between game updates), Tolk/external library calls, and game API calls that may behave unexpectedly. Normal code paths use null-checks, not try-catch.
3. **DebugLogger always, MelonLogger for critical:** Use `DebugLogger.Log()` for diagnostic info (only active in debug mode). Use `MelonLogger.Warning/Error()` for problems that persist outside debug mode (DLL not found, initialization failure).

### Defensive Programming

**Core rule:** Be null-safe AND log unexpected states.

```csharp
// BAD: Hides errors silently - you'll never know something is null
var text = panel?.GetComponentInChildren<Text>()?.text ?? "Unknown";

// GOOD: Null-safe AND logged
var textComp = panel?.GetComponentInChildren<Text>();
if (textComp == null)
{
    Logger.Warning("Text component not found in panel");
    ScreenReader.Say("Element not readable");
    return;
}
var text = textComp.text;
```

**For Reflection (prone to break on game updates):**
```csharp
// Catch specific exceptions, not everything
try
{
    var value = fieldInfo.GetValue(obj);
}
catch (TargetException ex)
{
    Logger.Warning($"Field access failed - game updated? {ex.Message}");
}
```

### Graceful Degradation

When something fails, don't crash - provide useful feedback:

```csharp
public void AnnounceInventory()
{
    var items = GetItems();
    if (items == null || items.Count == 0)
    {
        Announce("Inventory empty or not available");
        return;
    }
    // Continue normally
}
```

**Why both matter:**
- Without null-checks: Mod crashes on missing UI elements
- Without logging: You'll never know WHY something doesn't work

## Testing Considerations

- Test with actual screen reader software
- Verify announcements are clear and not too verbose
- Ensure keyboard navigation reaches all interactive elements
- Test with the screen off to simulate blind user experience
- Get feedback from blind users when possible

## Dos & Don'ts

### DO
- Use Tolk (or equivalent) for screen reader output
- Keep announcements short and informative
- Cache object references (not values) to avoid repeated lookups
- Add a `GetHelpText()` method to handlers for F1 help
- Test with an active screen reader

### DON'T
- No long announcements that block the screen reader
- No tables or ASCII art in output
- No redundant announcements (same info repeated)
- **NEVER override game keys** - check game keybindings first!
- No expensive search operations in Update loops (cache references, not values!)
- **NEVER silently fall back to cached values** when a live read fails — log it, announce it, fail visibly
- **NEVER bypass game methods** - use original pickup/buy/sell methods so the game stays in sync

## Common Pitfalls

- Announcing too much information at once
- Not announcing important state changes
- Inconsistent key bindings across different screens
- Overriding keys that screen reader users expect to work normally
- Assuming visual context that isn't announced
- Not handling rapid repeated key presses gracefully
- Polling every frame instead of using intervals or change detection
- Bypassing game methods (direct inventory manipulation) - breaks achievements, sounds, stats
- Matching widgets by name instead of full path — grids can reuse widget names across instances (e.g., two category grids both having `ItemIcon_L04`). Match on the full instance path to avoid reading stale/wrong data
- Gating poll functions on context variables that get cleared by other handlers — use module-internal state for self-gating instead
- Tracking dialogs by widget instance ID when the game reuses instances — track by content (e.g., header text) to detect new vs. same dialog
- Blindly queuing description/detail text without comparing to what was already spoken — detail fields can contain the item name itself, causing double announcements
- Taking the last match when reading from widgets with multiple TextBlock layers (template + real data, or current + stale) — take the first non-template match instead
- Using Lua `%w` in patterns to match widget names — `%w` does NOT match underscores, which are ubiquitous in UE widget names

---

## Unity-Specific Reference

*This section is only relevant for Unity games.*

### UI Detection

**Typical Unity UI Hierarchy:**
```
Canvas
└── Panel (e.g., "InventoryPanel")
    ├── Header (Title)
    ├── Content
    │   └── ScrollView
    │       └── Items (List)
    └── Buttons (Actions)
```

**Important Components to Search For:**
- `Text` / `TextMeshProUGUI` - Labels and text display
- `Button` - Clickable elements
- `Toggle` - On/off switches
- `Slider` - Value adjusters
- `InputField` - Text input
- `ScrollRect` - Scrollable lists

**Checking UI State:**
```csharp
// Is panel active?
bool isOpen = panel != null && panel.activeInHierarchy;

// Is button interactable?
bool canClick = button != null && button.interactable;

// Read text safely
string text = textComponent?.text ?? "";
```

### Unity Quick Reference

**Finding GameObjects:**
```csharp
var obj = GameObject.Find("Name");  // Slow - cache the reference!
var all = GameObject.FindObjectsOfType<Button>();
```

**Getting Components:**
```csharp
var text = obj.GetComponent<Text>();
var text = obj.GetComponentInChildren<Text>();
var allTexts = obj.GetComponentsInChildren<Text>();
```

**Navigating Hierarchy:**
```csharp
var child = parent.transform.Find("ChildName");
foreach (Transform child in parent.transform) { }
```

**Active State:**
```csharp
bool isActive = obj.activeInHierarchy;
obj.SetActive(true);
```

**Input Handling:**
```csharp
if (Input.GetKeyDown(KeyCode.F1)) { }  // Pressed once
if (Input.GetKey(KeyCode.LeftShift)) { }  // Held down
```

---

## Quick Reference: Best Practices

1. **Only announce on changes** - Not every frame
2. **Always include position** - "X of Y" for lists
3. **Explicit empty states** - Never silence
4. **Confirm actions** - What was done + new state
5. **Announce available commands** - Key hints when panel opens
6. **Use queued for details** - Don't interrupt main info
7. **Consistent patterns** - Same actions = same announcements
8. **Enable logging** - Essential for debugging
