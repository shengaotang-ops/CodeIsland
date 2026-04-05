# Floating Buddy Pet — Design Spec

## Overview

Replace the notch-based UI with a floating buddy pet that lives anywhere on screen. The buddy shows session status via color/glow, and expands into a compact panel on click. No notch dependency — works on any Mac without blocking menu bar icons.

## Buddy Widget (Collapsed State)

- **Size**: 48×48 pixels
- **Content**: User's Claude Code buddy (ASCII art or emoji, from `BuddyReader`)
- **Position**: Draggable anywhere on screen. Persists position to `UserDefaults` between launches
- **Window**: `NSPanel` with `.floating` level, borderless, transparent background
- **Always on top**: Floats above other windows but below modal dialogs

### State Indicators (Color/Glow)

The buddy has a subtle glow ring that changes color based on the most urgent session state:

| State | Glow Color | Meaning |
|-------|-----------|---------|
| Idle / no sessions | None (dim) | Nothing happening |
| Processing | Green (#4ADE80) | Claude is working |
| Waiting for input | Orange (#FBBF24) | Session finished, needs you |
| Waiting for approval | Red (#F87171) | Permission request pending |

Priority: approval > waiting for input > processing > idle. The glow pulses gently for attention-needed states (orange/red).

### Dragging

- Click and drag to move the buddy anywhere on screen
- Short click (no drag) expands the panel
- Position saved to `UserDefaults` on drag end
- Default initial position: bottom-right corner, 20px from edges

## Panel (Expanded State)

Clicking the buddy expands it into a compact floating panel anchored to the buddy's position.

### Layout

- **Size**: ~320×400px (grows with content, max 500px height)
- **Anchor**: Panel appears above/below the buddy depending on screen position (avoids going off-screen)
- **Background**: Dark translucent (`NSVisualEffectView` with `.hudWindow` material)
- **Corner radius**: 12px
- **Shadow**: Subtle drop shadow

### Content

Reuses existing views with minimal modification:

1. **Session list** — Compact version of `ClaudeInstancesView`
   - Each row: project name, status dot, buddy emoji, duration
   - Tap row: show chat for that session
   - Terminal icon button: jump to terminal (existing `TerminalJumper` logic)

2. **Chat view** — Reuses existing `ChatView`
   - Back button to return to session list
   - Shows full conversation with tool results

3. **Approval bar** — Shows approve/deny buttons when a session needs permission

### Dismissal

- Click outside the panel: collapse back to buddy
- Press Escape: collapse back to buddy
- Jump to terminal: collapse and jump

## Architecture

### New Files

```
ClaudeIsland/
├── UI/
│   ├── Window/
│   │   └── BuddyWindowController.swift    # NSWindowController for floating buddy
│   ├── Views/
│   │   ├── BuddyFloatingView.swift        # 48×48 buddy with glow ring
│   │   └── BuddyPanelView.swift           # Expanded panel container
│   └── Components/
│       └── BuddyGlowRing.swift            # Animated glow ring component
├── Core/
│   └── BuddyPanelViewModel.swift          # Panel state (collapsed/expanded, content type)
```

### Reused Existing Components

- `BuddyReader` — buddy species/stats calculation
- `BuddyASCIIView` / `EmojiPixelView` — buddy rendering
- `ClaudeSessionMonitor` — session state tracking
- `ChatHistoryManager` — chat content
- `ChatView` — chat display (may need minor sizing adjustments)
- `ClaudeInstancesView` — session list (compact variant)
- `TerminalJumper` — jump to terminal
- `HookSocketServer` — receives events from Claude Code
- `SoundManager` — notification sounds

### Modified Files

- `AppDelegate.swift` — Launch `BuddyWindowController` instead of `NotchWindowController`
- `Settings.swift` — Add setting to choose UI mode (notch vs floating buddy)
- `WindowManager.swift` — Support both window types

### Window Setup

```swift
// BuddyWindowController creates a borderless, transparent NSPanel
let panel = NSPanel(
    contentRect: NSRect(x: 0, y: 0, width: 48, height: 48),
    styleMask: [.borderless, .nonactivatingPanel],
    backing: .buffered,
    defer: false
)
panel.level = .floating
panel.isOpaque = false
panel.backgroundColor = .clear
panel.hasShadow = false
panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
```

### State Flow

```
HookSocketServer (events from Claude Code)
    ↓
SessionStore / ClaudeSessionMonitor
    ↓
BuddyPanelViewModel (determines glow color, panel content)
    ↓
BuddyFloatingView (glow ring) / BuddyPanelView (expanded panel)
```

### Panel Expand/Collapse

- `BuddyPanelViewModel.isExpanded` toggles between buddy-only and panel
- When expanding: animate buddy window size from 48×48 to panel size
- When collapsing: animate back to 48×48
- Use `withAnimation(.spring(...))` for smooth transitions

### Notification Suppression

Reuse the same logic from the notch branch:
- Check `isSessionTerminalFrontmost` per session
- Only show glow alerts for unfocused sessions
- Sound plays only for unfocused sessions

## Settings

Add a UI mode toggle in the existing settings menu:

- **Notch mode** (default on notched Macs) — existing behavior
- **Floating buddy mode** — new floating pet UI

Both modes share the same backend (hooks, session monitoring, chat history). Only the window/view layer differs.

## Out of Scope

- Custom buddy skins or animations beyond glow
- Multiple buddy instances
- Buddy walking/moving animations
- Integration with other apps besides terminals
- macOS widgets or menu bar extra
