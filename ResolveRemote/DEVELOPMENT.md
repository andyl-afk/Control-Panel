# Resolve Remote — Development Guide

User-facing setup is in [README.md](README.md). This is the maintainer/dev
document: building both apps, the CLI, the protocol, and distribution.

## Repo layout

```
ResolveRemote/
  iOS/ResolveRemote/        iPhone app sources (added to ResolveRemote.xcodeproj)
  macOS-app/
    ResolveRemoteHelper/    Menu bar app sources (Xcode app target, see below)
  macOS-helper/             Swift Package
    Sources/
      ResolveHelperKit/     Shared server/sidecar/keyboard logic + resolve_bridge.py
      ResolveHelper/        Developer CLI (thin wrapper over the Kit)
```

All helper logic lives in **ResolveHelperKit** — the CLI and the menu bar
app are both thin shells over `HelperCore`. Never duplicate logic between
them.

## Developer CLI

```sh
cd ResolveRemote/macOS-helper
swift run ResolveHelper                # dry-run: logs commands, sends no keys
swift run ResolveHelper --send-keys    # sends keyboard events
swift run ResolveHelper --port 50000   # custom port
```

Note the CLI's default is **dry-run** (safe for debugging); the menu bar
app's default is **send-keys** (its dry-run is a menu toggle).

Smoke test without a phone:

```sh
echo '{"v":1,"seq":1,"mode":"edit","cmd":"ping","ts":0}' | nc localhost 49321
```

The Python sidecar can be tested standalone — it speaks newline JSON on
stdin/stdout (`Sources/ResolveHelperKit/resolve_bridge.py`).

## Creating the menu bar app target (one-time Xcode setup)

The sources are in `macOS-app/ResolveRemoteHelper/`. In the existing
`ResolveRemote.xcodeproj`:

1. **File → New → Target… → macOS → App.** Product Name:
   **Resolve Remote Helper**, Interface SwiftUI. Delete the template
   `ContentView.swift` and the template App file.
2. Add the two source files from `macOS-app/ResolveRemoteHelper/` to the
   new target (reference, don't copy).
3. **Add the local package:** File → Add Package Dependencies… →
   Add Local… → select `ResolveRemote/macOS-helper`. Link the
   **ResolveHelperKit** library product to the *Resolve Remote Helper*
   target only (the iOS app must NOT link it).
4. Target settings:
   - Info: **Application is agent (UIElement)** = YES (`LSUIElement`) — menu
     bar only, no Dock icon.
   - Signing & Capabilities: **remove the App Sandbox** capability. The
     helper synthesizes keyboard events, spawns python3, and accepts
     LAN connections — none of which work sandboxed.
   - Minimum deployment: macOS 13.
5. Build & run. The dial icon appears in the menu bar; the first launch
   without Accessibility shows the one-time explainer alert.

## iOS app Info.plist keys

The iOS target needs both of these (target → Info tab):

- `NSLocalNetworkUsageDescription` — "Resolve Remote connects to the Mac
  helper on your local network to control DaVinci Resolve."
- `NSBonjourServices` (Array) — one item: `_resolveremote._tcp`
  **(new in Phase 9 — discovery silently fails without it).**

## Protocol

Newline-delimited JSON over TCP (default port 49321), advertised over
Bonjour as `_resolveremote._tcp`. Phone → helper commands carry
`v/seq/mode/cmd/ts` plus per-command fields (`ticks`, `level`, `target`,
`steps`, `speed`, `param`, `enabled`, `name`, `dx`, `dy`, `index`).
`mode:"edit"` commands drive the keyboard path; `mode:"color"` commands are
forwarded verbatim to the Python sidecar, whose stdout lines
(`color_state`, `preset_list`, `preset_applied`, `still_grabbed`) are
broadcast back to all clients. Tunable constants (step sizes, clamps,
strengths, rate limits) are grouped at the top of `resolve_bridge.py` and
of the relevant Swift files.

## Finding the Mac's IP (manual fallback)

The helper menu shows it; or `ipconfig getifaddr en0`; or System
Settings → Wi-Fi → Details. Personal Hotspot/USB-C tethering gives the
lowest latency (helper menu shows the per-interface addresses).

## Distribution notes

- **Mac helper app:** for anyone outside your own machine, sign with a
  **Developer ID Application** certificate and **notarize** (Xcode →
  Product → Archive → Distribute App → Direct Distribution handles
  notarization). Unsigned builds trip Gatekeeper and, worse, lose their
  Accessibility grant on every rebuild.
- **iOS app:** distribute to a team via **TestFlight** (requires the Apple
  Developer Program) or install directly from Xcode for a couple of
  devices (7-day expiry on a free account, 1 year with the program).
- Per-phase acceptance checklists live in `PHASE_1..9_TESTING.md`; run the
  latest phase plus a quick pass of Edit/Colour basics before sharing a
  build.
