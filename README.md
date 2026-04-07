<div align="center">

<img src="ClaudeIsland/Assets.xcassets/AppIcon.appiconset/icon_128x128.png" width="128" height="128" alt="CodeIsland" />

# CodeIsland

**Your AI agents live in a floating buddy on your desktop.**

This is a passion project built purely out of personal interest. It is **free and open-source** with no commercial intentions whatsoever. I welcome everyone to try it out, report bugs, share it with your colleagues, and contribute code. Let's build something great together!


[![GitHub stars](https://img.shields.io/github/stars/shengaotang-ops/CodeIsland?style=social)](https://github.com/shengaotang-ops/CodeIsland/stargazers)

[![Website](https://img.shields.io/badge/website-shengaotang-ops.github.io%2FCodeIsland-7c3aed?style=flat-square)](https://xmqywx.github.io/CodeIsland/)
[![Release](https://img.shields.io/github/v/release/shengaotang-ops/CodeIsland?style=flat-square&color=4ADE80)](https://github.com/shengaotang-ops/CodeIsland/releases)
[![macOS](https://img.shields.io/badge/macOS-14%2B-black?style=flat-square&logo=apple)](https://github.com/shengaotang-ops/CodeIsland/releases)
[![License](https://img.shields.io/badge/license-CC%20BY--NC%204.0-green?style=flat-square)](LICENSE.md)

**If you find this useful, please give it a star! It keeps us motivated to improve.**


</div>

---

A native macOS app that puts a floating buddy on your desktop as a real-time control surface for AI coding agents. Monitor sessions, approve permissions, jump to terminals, and hang out with your Claude Code buddy — all without leaving your flow.

## Features

### Floating Buddy

A draggable buddy pet that lives on your desktop with a glowing ring that reflects session state:

- **Animated buddy** — your Claude Code `/buddy` pet rendered as pixel art with idle animations
- **Glow ring** — color indicates state:
  - 🟦 Cyan = working
  - 🟧 Amber = needs approval
  - 🟩 Green = done / waiting for input
  - 🔴 Red = error
- **Click to expand** — opens a session panel right next to the buddy
- **Draggable** — position anywhere on screen, position persists across launches
- **Pixel Cat Mode** — toggle to show the hand-drawn pixel cat instead of your buddy

### Session Panel

Click the buddy to see all your Claude Code sessions in a flat list:

- **Pixel cat face** per session with state-specific expressions (blink, eye-dart, heart eyes on done, X eyes on error)
- **Auto-detected terminal** — shows Ghostty, Warp, iTerm2, cmux, Terminal, VS Code, Cursor, etc.
- **Task title** — displays your first message or Claude's summary, not just the folder name
- **Duration badge** — how long each session has been running
- **Terminal jump button** — click to jump to the exact terminal tab (via cmux/Ghostty AppleScript)
- **Subagent tracking** — see active subagents nested under each session
- **Inline approval** — approve or deny permission requests without switching windows
- **Chat view** — open a chat panel for any session

### Claude Code Buddy Integration

Full integration with Claude Code's `/buddy` companion system:

- **Accurate stats** — species, rarity, eye style, hat, shiny status, and all 5 stats (DEBUGGING, PATIENCE, CHAOS, WISDOM, SNARK) computed using the exact same Bun.hash + Mulberry32 algorithm as Claude Code
- **Dynamic salt detection** — reads the actual salt from your Claude Code binary, supports patched installs (any-buddy compatible)
- **ASCII art sprite** — all 18 buddy species rendered as animated ASCII art with idle animation sequence (blink, fidget), matching Claude Code's terminal display
- **Buddy card** — left-right layout: ASCII sprite + name on the left, ASCII stat bars `[████████░░]` + personality on the right
- **Rarity stars** — ★ Common to ★★★★★ Legendary with color coding
- **18 species supported** — duck, goose, blob, cat, dragon, octopus, owl, penguin, turtle, snail, ghost, axolotl, capybara, cactus, robot, rabbit, mushroom, chonk

### Permission Approval

Approve or deny Claude Code's permission requests right from the notch:

- **Code diff preview** — see exactly what will change before allowing (green/red line highlighting)
- **File path display** — warning icon + tool name + file being modified
- **Deny/Allow buttons** — with keyboard hint labels
- **Hook-based protocol** — responses sent via Unix socket, no terminal switching needed

### Pixel Cat Companion

A hand-drawn pixel cat with 6 animated states:

| State | Expression |
|-------|-----------|
| Idle | Black eyes, gentle blink every 90 frames |
| Working | Eyes dart left/center/right (reading code) |
| Needs You | Eyes + right ear twitches |
| Thinking | Closed eyes, breathing nose |
| Error | Red X eyes |
| Done | Green heart eyes + green tint overlay |

### 8-bit Sound System

Chiptune alerts for every event:

| Event | Default |
|-------|---------|
| Session start | ON |
| Processing begins | OFF |
| Needs approval | ON |
| Approval granted | ON |
| Approval denied | ON |
| Session complete | ON |
| Error | ON |
| Context compacting | OFF |

Each sound can be toggled individually. Global mute and volume control available.

## Settings

| Setting | Description |
|---------|-------------|
| **Screen** | Choose which display shows the notch (Auto, Built-in, or specific monitor) |
| **Notification Sound** | Select alert sound style |
| **Pixel Cat Mode** | Switch buddy icon between pixel cat and buddy emoji animation |
| **Smart Suppression** | Suppress notifications for sessions you're actively watching |
| **Auto Collapse** | Collapse panel when mouse leaves |
| **Language** | Auto (system) / English / Chinese |
| **Launch at Login** | Start CodeIsland automatically when you log in |
| **Hooks** | Install/uninstall Claude Code hooks in `~/.claude/settings.json` |
| **Accessibility** | Grant accessibility permission for terminal window focusing |

## Terminal Support

CodeIsland auto-detects your terminal from the process tree:

| Terminal | Detection | Jump-to-Tab |
|----------|-----------|-------------|
| cmux | Auto | AppleScript (by working directory) |
| Ghostty | Auto | AppleScript (by working directory) |
| Warp | Auto | Activate only (no tab API) |
| iTerm2 | Auto | AppleScript |
| Terminal.app | Auto | Activate |
| Alacritty | Auto | Activate |
| Kitty | Auto | Activate |
| WezTerm | Auto | Activate |
| VS Code | Auto | Activate |
| Cursor | Auto | Activate |
| Zed | Auto | Activate |

## Build from Source

```bash
git clone https://github.com/shengaotang-ops/CodeIsland.git
cd CodeIsland
xcodebuild -project ClaudeIsland.xcodeproj -scheme ClaudeIsland \
  -configuration Release CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  DEVELOPMENT_TEAM="" build
```

### Requirements

- macOS 14+ (Sonoma)
- [Bun](https://bun.sh) for accurate buddy stats (optional, falls back to basic info)

## How It Works

1. **Zero config** — on first launch, CodeIsland installs hooks into `~/.claude/settings.json`
2. **Hook events** — a Python script (`codeisland-state.py`) sends session state to the app via Unix socket (`/tmp/codeisland.sock`)
3. **Permission approval** — for `PermissionRequest` events, the socket stays open until you click Allow/Deny, then sends the decision back to Claude Code
4. **Buddy data** — reads `~/.claude.json` for name/personality, runs `buddy-bones.js` with Bun for accurate species/rarity/stats
5. **Terminal jump** — uses AppleScript to find and focus the correct terminal tab by matching working directory

## Credits

Forked from [Claude Island](https://github.com/farouqaldori/claude-island) by farouqaldori. Rebuilt with pixel cat animations, buddy integration, cmux support, i18n, and minimal glow-dot design.

## License

CC BY-NC 4.0 — free for personal use, no commercial use.
