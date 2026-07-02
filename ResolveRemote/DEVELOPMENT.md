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

> **Note on file locations:** Xcode moves target sources into a
> `Resolve Remote Helper/` group folder when you add them, so the helper
> Swift files live at `ResolveRemote/ResolveRemote/Resolve Remote Helper/`,
> not the original `macOS-app/` path. That's expected — edits happen there.

### Gotchas we actually hit (read this if the build/run fails)

- **"Listener failed: Operation not permitted" (server shows Stopped):**
  the App Sandbox is still active. Removing the *capability card* often
  leaves an `.entitlements` file (with `com.apple.security.app-sandbox`)
  still enforcing it. Delete that entitlements file (or set app-sandbox
  to NO) **and** clear **Build Settings → Code Signing Entitlements** if
  it still points there, then Clean Build Folder (⇧⌘K) and rerun. On
  first run, click **Allow** on the macOS incoming-connections prompt; on
  macOS 15+, also enable the app under System Settings → Privacy &
  Security → Local Network.
- **`@Published` + `didSet`** in a class with a custom `init` triggers
  "objectWillChange used before being initialized" — don't combine them;
  use plain `@Published private(set)` + setter methods (see
  `HelperAppState`).
- **A class conforming to `ObservableObject` needs ≥1 `@Published`
  property**, or it won't synthesize `objectWillChange` and fails to
  conform. `HelperAppDelegate` deliberately does NOT conform (it isn't
  observable — the state is).
- **`Unable to resolve module 'AppKit'/'ApplicationServices'`** while
  building means `ResolveHelperKit` is compiling for iOS — make sure the
  iOS app target does NOT link it and you're building the helper scheme
  for **My Mac**.

### Keeping the Xcode project in git (avoids "my setup reverted" pain)

`project.pbxproj` is tracked. The cloud agent adds `.swift` files on disk
but can't register them in the project, so **after any structural change
in Xcode (new target, added files, package link) commit and push
`project.pbxproj` yourself** from Terminal (Xcode's Source Control → Pull
can silently discard uncommitted project changes):

```sh
git add -A && git commit -m "Update Xcode project" && git push
```

Once committed, `git pull` brings source changes without reverting your
project config. Only brand-new source files added in a later phase need a
one-time drag into the target (then commit the project again).

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

## Capability Probe

A diagnostic that discovers what the installed DaVinci Resolve actually
supports, so the UI can enable/label controls honestly.

- Command (app → helper): `{"v":1,"mode":"system","cmd":"capability_probe"}`.
  Routed by `CommandRouter` (mode `system`) to the sidecar, which handles it
  on the reader thread (like `bypass`) — it works with no project/clip and
  never blocks grading.
- Response (helper → all clients): one line
  `{"v":1,"type":"capability_state", resolve_connected, product_name,
  version_string, current_page, current_project, current_timeline,
  current_video_item, features:{name:status}, warnings:[], errors:[]}` where
  status is `supported | unsupported | unknown | error`.
- The sidecar (`resolve_bridge.py`) introspects via `has_method` /
  `feature_from_method` / `safe_call`; one failed check never aborts the
  probe. AI features and the Photo page default to `unknown` and are never
  invoked (the probe must not disrupt the user or run expensive actions).
- Surfaced in the app under Settings → DIAGNOSTICS → Resolve capabilities
  (Probe / Copy JSON), in the menu bar app ("Probe Resolve Capabilities"),
  and in the CLI (`[capability]` log lines).
- **Caveat:** the probe only proves availability on *this* installed
  system — it does not guarantee a feature works in every project state.

## iPad dashboard + capability gating (Phase 12)

`Views/iPad/` holds an iPad-only control surface (page rail: Edit / Colour /
Fairlight / Settings) selected by **idiom** (`userInterfaceIdiom == .pad`),
never by size class — big iPhones in landscape must keep the phone layout.

Gating rules (`FeatureStatus` from the capability probe + local `wired` flag):

| Status      | UI behaviour                                              |
| ----------- | --------------------------------------------------------- |
| supported   | enabled **only if** the control is also `wired`           |
| unknown     | "Experimental" badge, disabled                             |
| missing     | (no probe yet) treated as unknown/Experimental, disabled   |
| unsupported | "Unsupported" badge, disabled                              |
| error       | "Error" badge, disabled                                    |
| not wired   | "Not wired" badge regardless of status — never executes    |

Not-wired/blocked taps call a local `onBlocked(message)` → transient toast
in the status strip; **nothing is ever sent to the helper** for unproven
controls. Dangerous-but-unwired actions (Reset Grade) additionally carry a
"Dangerous" badge.

Wired command inventory reused by the iPad UI (all pre-existing): edit
keyboard commands (jog/shuttle/transport/shortcuts/marker), `color_delta`,
`param_delta` (contrast/pivot/sat/temp/tint), `balance_delta`,
`color_reset`, `set_node`, `bypass`, `grab_still`, `list_presets`/
`apply_preset`, `color_status`, `capability_probe`. Temp/Tint are CDL
approximations (Slope skew) and are labelled "CDL approx".

The helper re-broadcasts its cached `capability_state` to newly connected
clients (HelperCore), and the iPad auto-sends one `capability_probe` on
connect, so the dashboard gates correctly without manual probing. The iPad
UI exposes only proven or explicitly experimental controls — never fake
support.

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
