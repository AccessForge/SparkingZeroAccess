# State Management Guide for Accessibility Mods

This guide explains how to manage multiple handlers that respond to the same keys without conflicts.

## When Do You Need This?

**Simple mods (1-2 handlers):** You probably don't need a full state manager. A simple boolean flag per handler is enough.

**Complex mods (3+ handlers on same keys):** When multiple handlers can react to Enter, Escape, or arrow keys, you need coordination. This guide is for you.

**Signs you need state management:**
- Pressing Enter triggers two actions at once
- Closing one menu accidentally activates another
- Cached data shows wrong information after switching contexts

---

## The Problem

When multiple handlers can react to the same keys, conflicts arise:

1. **Double processing**: Handler A processes Enter, then Handler B also processes Enter in the same frame
2. **State conflicts**: Handler A is active, but Handler B also tries to become active
3. **Stale data**: Handler B uses cached data from before the state change

### Why does double processing happen?

`Input.GetKeyDown()` returns `true` for the **entire frame**. If the update order is:

1. HandlerA.Update() - processes Enter, ends its state
2. HandlerB.Update() - still sees Enter as "pressed"

Both handlers process the same key press - user presses Enter once, but two actions happen!

---

## Solution 1: Simple Flag (for small mods)

For mods with only 2-3 handlers, a simple approach works:

```csharp
public class ModMain
{
    private bool _menuHandlerActive = false;
    private bool _inventoryHandlerActive = false;

    public void Update()
    {
        // Only one can be active
        if (_menuHandlerActive)
        {
            _menuHandler.Update();
        }
        else if (_inventoryHandlerActive)
        {
            _inventoryHandler.Update();
        }
        else
        {
            // Default handler when nothing else is active
            _navigationHandler.Update();
        }
    }
}
```

**Advantages:** Simple, easy to understand
**Disadvantages:** Doesn't scale well, no automatic cleanup

---

## Solution 2: Central State Manager (recommended for complex mods)

A central `AccessStateManager` controls which handler is currently active.

**Template available:** Use `templates/shared/AccessStateManager.cs.template` as starting point. It includes Context tracking, events, ForceReset, IsInputBlocked, delayed announcements, and an Escape handling pattern via Harmony patch. The template is based on proven production code.

### Basic Implementation (simplified — see template for full version)

```csharp
public static class AccessStateManager
{
    public enum State
    {
        None,           // No handler active - default state
        MenuNavigation, // Main menu active
        Inventory,      // Inventory open
        Dialog,         // Dialog system active
        // Add your states here...
    }

    public static State Current { get; private set; } = State.None;

    // Event for handlers to react to state changes
    public static event Action<State, State> OnStateChanged;

    /// <summary>
    /// Attempts to enter a state. Auto-exits previous state if needed.
    /// </summary>
    public static bool TryEnter(State state)
    {
        if (Current == state) return true; // Already in this state

        var oldState = Current;

        // Exit previous state
        if (Current != State.None)
        {
            Current = State.None;
        }

        Current = state;
        OnStateChanged?.Invoke(oldState, state);
        return true;
    }

    /// <summary>
    /// Exits a state (only if this state is currently active).
    /// </summary>
    public static void Exit(State state)
    {
        if (Current == state)
        {
            var oldState = Current;
            Current = State.None;
            OnStateChanged?.Invoke(oldState, State.None);
        }
    }

    /// <summary>
    /// Checks if a state can be entered.
    /// </summary>
    public static bool CanEnter(State state)
    {
        return Current == State.None || Current == state;
    }

    /// <summary>
    /// Checks if a specific state is currently active.
    /// </summary>
    public static bool IsActive(State state)
    {
        return Current == state;
    }
}
```

### Using the State Manager in Handlers

```csharp
public class InventoryHandler
{
    private bool _isActive = false;

    public void Update()
    {
        // Check if we're allowed to become active
        if (!AccessStateManager.CanEnter(AccessStateManager.State.Inventory))
            return;

        // Open inventory with I key
        if (Input.GetKeyDown(KeyCode.I) && !_isActive)
        {
            if (AccessStateManager.TryEnter(AccessStateManager.State.Inventory))
            {
                _isActive = true;
                OpenInventory();
            }
        }

        // Only process input if we're active
        if (!_isActive) return;

        // Close with Escape
        if (Input.GetKeyDown(KeyCode.Escape))
        {
            CloseInventory();
            _isActive = false;
            AccessStateManager.Exit(AccessStateManager.State.Inventory);
        }

        // Handle other input...
    }
}
```

---

## Solving Input Bleed-Through

Even with a state manager, the "same frame" problem remains. When Handler A processes Enter and exits, Handler B might still see Enter as pressed.

### Solution: Frame-based Input Lock

The handler that processed the input tells others that the input is "consumed" for this frame.

**Option A: Central input consumption (cleaner)**

```csharp
public static class InputHelper
{
    private static int _lastConsumedFrame = -1;
    private static KeyCode _lastConsumedKey = KeyCode.None;

    /// <summary>
    /// Call this after processing a key to prevent other handlers
    /// from processing the same key in this frame.
    /// </summary>
    public static void ConsumeKey(KeyCode key)
    {
        _lastConsumedFrame = Time.frameCount;
        _lastConsumedKey = key;
    }

    /// <summary>
    /// Check if a key was already consumed this frame.
    /// </summary>
    public static bool IsKeyConsumed(KeyCode key)
    {
        return Time.frameCount == _lastConsumedFrame && _lastConsumedKey == key;
    }

    /// <summary>
    /// Replacement for Input.GetKeyDown that respects consumption.
    /// </summary>
    public static bool GetKeyDown(KeyCode key)
    {
        if (IsKeyConsumed(key)) return false;
        return Input.GetKeyDown(key);
    }
}
```

Usage:
```csharp
// In any handler
if (InputHelper.GetKeyDown(KeyCode.Return))
{
    DoAction();
    InputHelper.ConsumeKey(KeyCode.Return);
}
```

**Option B: Direct notification (more explicit)**

```csharp
// In the handler that should NOT react
private int _inputConsumedFrame = -1;

public void NotifyInputConsumed()
{
    _inputConsumedFrame = Time.frameCount;
}

private void HandleInput()
{
    if (Input.GetKeyDown(KeyCode.Return))
    {
        // Check if Enter was already consumed this frame
        if (Time.frameCount == _inputConsumedFrame)
            return;

        // Process normally...
    }
}

// In the handler that processes Enter and then hands off
private void ConfirmSelection()
{
    // Do the action...

    // Exit state
    AccessStateManager.Exit(AccessStateManager.State.MyState);

    // Notify the next handler
    _defaultHandler?.NotifyInputConsumed();
}
```

---

## Preventing Stale Data on State Changes

When a handler becomes inactive, any stored data becomes stale. For accessibility mods this is critical: a blind player trusts what the screen reader announces. Stale data means wrong announcements with no way for the player to notice.

### The Problem

```
1. NavigationHandler active, _currentObjects = [Tavern, Road]
2. User opens BuildingMenu overlay
3. NavigationHandler deactivates, but _currentObjects remains
4. User closes overlay
5. NavigationHandler reactivates
6. _currentObjects still shows old data — player hears wrong info!
```

### Solution: Clear on exit, always refresh on re-entry

```csharp
public class NavigationHandler
{
    private List<GameObject> _currentObjects;

    public void Initialize()
    {
        AccessStateManager.OnStateChanged += OnStateChanged;
    }

    private void OnStateChanged(State oldState, State newState)
    {
        // When we're deactivated
        if (oldState == State.Navigation && newState != State.Navigation)
        {
            // Clear cached data!
            _currentObjects = null;
            _currentIndex = 0;
        }

        // When we're reactivated
        if (newState == State.Navigation)
        {
            // Refresh data
            RefreshCurrentObjects();
        }
    }
}
```

---

## Debouncer for Rapid Key Presses

Prevents the same key from triggering multiple times when held or pressed rapidly.

```csharp
public class Debouncer
{
    private float _lastTime = 0f;
    private readonly float _interval;

    public Debouncer(float interval = 0.15f)
    {
        _interval = interval;
    }

    public bool CanExecute()
    {
        if (Time.unscaledTime - _lastTime < _interval)
            return false;

        _lastTime = Time.unscaledTime;
        return true;
    }

    public void Reset()
    {
        _lastTime = 0f;
    }
}
```

Usage:
```csharp
private Debouncer _debounce = new Debouncer(0.15f);

if (Input.GetKeyDown(KeyCode.Return) && _debounce.CanExecute())
{
    DoAction();
}
```

**Note:** Each handler has its own Debouncer. This doesn't solve cross-handler issues - use InputHelper.ConsumeKey for that.

---

## Handler Update Order

The order in which handlers update matters:

```csharp
// In ModMain.cs
void UpdateHandlers()
{
    // 1. Blocking handlers first (dialogs, popups)
    _dialogHandler?.Update();
    _popupHandler?.Update();

    // 2. Specific handlers (process and consume input)
    _inventoryHandler?.Update();
    _buildMenuHandler?.Update();

    // 3. Default/fallback handler last (checks if input was consumed)
    _navigationHandler?.Update();
}
```

---

## Quick Reference

**When to use what:**

- **1-2 handlers:** Simple boolean flags
- **3+ handlers on same keys:** Central state manager + input consumption
- **Rapid key press issues:** Debouncer
- **Stale data after state change:** OnStateChanged event + cache clearing

**Checklist for new handlers:**

- [ ] Register with AccessStateManager (if using it)
- [ ] Use InputHelper.GetKeyDown or check IsKeyConsumed
- [ ] Call ConsumeKey after processing shared keys (Enter, Escape, arrows)
- [ ] Clear cached data in OnStateChanged when deactivated
- [ ] Add handler to UpdateHandlers in correct order
- [ ] Test: Press Enter once → only ONE action should happen

**Common mistakes:**

1. **Forgot to consume input**: One Enter press triggers two actions
2. **Cache not cleared**: Stale data after state changes
3. **Wrong update order**: Default handler runs before specific handlers
4. **Exit before consume**: Always consume input before or immediately after exiting state

---

## Alternative Approaches

This guide presents one solution. Other valid approaches exist:

**Unity's new Input System:** Has built-in input consumption. Consider using it for new projects.

**Event-based architecture:** Instead of polling in Update(), handlers subscribe to input events. Cleaner but more setup.

**Priority-based input:** Handlers have priorities, highest priority that wants the input gets it.

Choose what fits your mod's complexity and your comfort level.
