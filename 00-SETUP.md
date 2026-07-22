# Setup — OwnFrame (Claude Code + XcodeBuildMCP + Spec Kit)

Order of steps to get started on the Mac. Everything here runs *there* — not in chat.

## Prerequisites (your current state)
- Dev account in place ✓
- Immich server over HTTPS with a **valid** certificate ✓ (local downgrades/self-signed come
  later)
- MQTT broker with **TLS** in place ✓
- Xcode 26.3+ (for Apple Xcode MCP + agent previews)
- Node (for `npx`), Python `uv` (for Spec Kit)

## 1. Create the Xcode Project
In Xcode: new app project, SwiftUI, target **iPadOS** (iPhone optional). Name e.g.
`ImmichSlideshow`. Set the minimum deployment on the target to what's specified in `CLAUDE.md`
(default iOS/iPadOS 18). Close the project — from here on, Claude Code works in the terminal.

## 2. Start Claude Code in the Project Folder
```
cd ~/Developer/ImmichSlideshow
claude
```

## 3. Connect XcodeBuildMCP (autonomous builds/tests)
```
claude mcp add --transport stdio XcodeBuildMCP --scope project \
  --env INCREMENTAL_BUILDS_ENABLED=true \
  --env XCODEBUILDMCP_DYNAMIC_TOOLS=true \
  -- npx -y xcodebuildmcp@latest
```
Optionally also add Apple's native Xcode MCP (from Xcode 26.3) for SwiftUI preview
verification — check the exact `xcrun mcpbridge` command for your Xcode version, it's still
changing.

## 4. Copy Files From This Bundle Into the Project
- `CLAUDE.md` → project root
- `docs/` → project-root/docs/

`CLAUDE.md` is loaded automatically by Claude Code on startup.

## 5. Initialize Spec Kit
```
uv tool install specify-cli --from git+https://github.com/github/spec-kit.git
specify init --here --ai claude
```
This creates `.specify/` (constitution, templates) + the Claude skills.
**Do not** rebuild this by hand — Spec Kit manages it itself.

## 6. Feed In the Constitution + First Spec
Paste content from this bundle into the Spec Kit commands:
- `docs/constitution-input.md` → content for `/speckit.constitution`
- `docs/spec-input-immichclient.md` → content for `/speckit.specify` (first feature)

Then the Spec Kit loop:
`constitution → specify → clarify → checklist → plan → tasks → analyze → implement`

## 7. Feature Order (= Spec Order)
1. **ImmichClient** (connect to server, album list, load assets) ← feasibility test
2. **SlideshowView** (full screen, timer, fade)
3. **Onboarding** (3 steps, keychain)
4. **PowerManager** (idle timer, brightness)
5. **Theme settings**
6. **HAControl** (MQTT/TLS, discovery) ← biggest chunk, last

Only once 1+2 run green is the rest worth it. See `docs/tdd-workflow.md`.
