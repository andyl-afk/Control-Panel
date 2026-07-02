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
`mode:"edit"` commands drive the keyboard path; `mode:"color"`,
`mode:"system"` and `mode:"fusion"` commands are forwarded verbatim to the
Python sidecar, whose stdout lines (`color_state`, `preset_list`,
`preset_applied`, `still_grabbed`, `capability_state`,
`fusion_capability_state`, …) are broadcast back to all clients. Tunable constants (step sizes, clamps,
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

`Views/iPad/` holds an iPad-only control surface (tabs: Edit / Colour /
Fusion / Deliver, plus Settings) selected by **idiom**
(`userInterfaceIdiom == .pad`), never by size class — big iPhones in
landscape must keep the phone layout. (The Fairlight tab was replaced by
Fusion in Phase 15; Fairlight remains only as an inert PAGES-rail button.)

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

**Phase 13** restyled the dashboard to the product mockup (top tab bar +
DELIVER placeholder, right PAGES rail + SHIFT, bottom Dashboard/Macros/
Settings bar, labelled green-play transport, all-knob adjustments, hue-ring
primary wheel, numbered custom-shortcut strip) — restyle only, no new wired
commands. **Phase 14 (queued):** wire the custom shortcut strip, the
SHORTCUT LAYOUT editor, GENERAL prefs (jog sensitivity / shuttle max / send
rate), and Macros.

The helper re-broadcasts its cached `capability_state` to newly connected
clients (HelperCore), and the iPad auto-sends one `capability_probe` on
connect, so the dashboard gates correctly without manual probing. The iPad
UI exposes only proven or explicitly experimental controls — never fake
support.

## Colour action smoke tests (Phase 14)

Settings → Diagnostics → Colour smoke tests proves the full round trip
(app → helper → sidecar → Resolve → broadcast → app) with visible JSON.

New `mode:"color"` commands (all reply with one
`{"type":"color_action_result","cmd":…,"ok":…,"message"/"reason"/"details"}`
line, broadcast to all clients):

- `reset_grade` — Resolve's ResetAllGrades on the current clip.
  **DESTRUCTIVE**: requires `"confirm": true`, otherwise the sidecar replies
  `{"type":"command_rejected","reason":"confirmation_required"}`. On success
  the app's shadow trims for the clip are purged and a forced color_state is
  broadcast.
- `set_lut` — requires `lut_path` (absolute paths are checked with isfile;
  relative names are attempted as Resolve-LUT-dir references). `node_index`
  defaults to the stepper-selected active node. Never picks a default LUT.
- `apply_drx` — requires an existing `drx_path`; shares the exact code path
  of the Looks presets (including the ApplyGradeFromDRX graph-re-fetch crash
  workaround and the trim purge). Never picks a default file.

Deliberately NOT duplicated: CDL nudges, colour context, targeted resets,
and Grab Still are already proven production commands (`color_delta`,
`param_delta`, `color_status`, `color_reset`, `grab_still`) — the smoke
panel sends those directly. Magic Mask / Smart Reframe remain status-only
(capability probe); they are never executed.

Safety rules: destructive/expensive actions need explicit confirmation
fields; path-taking actions need explicit paths; a probe saying "supported"
means *available*, not automatically *safe production behaviour*.

## Fusion capability probe (Phase 15)

Answers "what can Resolve Remote do with Fusion on this install" before any
Fusion UI is wired. The iPad FAIRLIGHT tab became FUSION; the Fusion mode
view and the Settings → Diagnostics → **Fusion capabilities** sheet are
probe-driven diagnostics, not the final surface.

Two `mode:"fusion"` commands, both handled on the sidecar's reader thread
(like `capability_probe` — they work with no project/clip and never block
grading):

- `fusion_probe` — pure introspection; emits one
  `{"v":1,"type":"fusion_capability_state", resolve_connected, product_name,
  version_string, current_page, current_project, current_timeline,
  current_video_item, fusion_object, comp_count, comp_names, current_comp,
  tool_count, features:{…}, warnings, errors}` line.
- `open_fusion_page` — the ONLY mutating Fusion action this phase
  (`resolve.OpenPage("fusion")`, success verified by re-reading
  `GetCurrentPage`); replies with one
  `{"type":"fusion_action_result","cmd":"open_fusion_page","ok":…,
  "page"/"reason"/"message"}` line (reasons: `no_resolve`, `unsupported`,
  `resolve_error`).

Probe invocation tiers (the honesty rule, in code comments too):

1. **Presence only, never invoked:** `OpenPage` and every comp/tool-mutating
   method — `LoadFusionCompByName`, `AddFusionComp`, `ImportFusionComp`,
   `ExportFusionComp`, `RenameFusionCompByName`, `DeleteFusionCompByName`,
   `comp.AddTool`, `tool.SetInput`. "supported" = the method exists, not
   that it was ever called. A fixed warning states this.
2. **Read-only calls, `safe_call`-wrapped:** `resolve.Fusion()`,
   `GetFusionCompCount()`, `GetFusionCompNameList()`,
   `fusion.GetCurrentComp()`, comp handle via `GetFusionCompByIndex(1)`.
3. **Comp internals, page-gated:** `comp.GetToolList(False)` / `ActiveTool`
   are only invoked while `current_page == "fusion"` — the probe NEVER
   switches the user's page (photo_page rule). Off the Fusion page they
   report `unknown` plus a "open it and re-probe" warning.

Surfaces: iPad Fusion tab (probe summary, wired Open Fusion Page, badged
inert comp/tool placeholders), iPad PAGES rail (FUSION is the one wired page
button, gated on the probed `open_fusion_page`), iPhone Settings sheet,
menu bar ("Probe Fusion Capabilities"), CLI (`[fusion]` lines). The helper
caches the last `fusion_capability_state` and re-broadcasts it to newly
connected clients, exactly like `capability_state`; the iPad auto-sends a
`fusion_probe` on connect.

The polished Fusion surface (tool grid, parameter knob, XY pad, macros,
comp actions) is a later phase and must wire only what this probe proves.

## Fusion action smoke tests (Phase 16)

Settings → Diagnostics → **Fusion smoke tests** proves the methods the
Phase-15 probe *found* actually *execute* — probe presence is not the same
as safe execution. Eleven `mode:"fusion"` commands, all handled on the
sidecar's reader thread; every reply is one
`{"type":"fusion_action_result","cmd":…,"ok":…,"message"/"reason"/
"details"}` line broadcast to all clients.

Read-only (no guard): `fusion_context`, `fusion_list_comps`,
`fusion_list_tools`, `fusion_active_tool` (no selected tool is ok:true, not
an error), `fusion_delete_comp_status` (reports whether delete exists —
**deletes nothing**, deliberately, this phase).

Path-taking: `fusion_export_comp` (requires `export_path`, parent folder
must exist, optional `index` defaulting to 1 — the API exports by index);
`fusion_import_comp` (requires `confirm:true` + an existing `import_path`).
No default paths are ever invented.

Guarded mutations (`confirm:true` or the sidecar replies
`command_rejected: confirmation_required`): `fusion_add_comp`,
`fusion_rename_comp` (index → name via GetFusionCompNameList, then
RenameFusionCompByName), `fusion_add_tool_test`, `fusion_set_input_test`.

Allowlists (constants at the top of `resolve_bridge.py`): tools —
TextPlus, Background, Merge, Transform only; inputs — StyledText (Text
tools, string), Size (Transform, float), Center (Transform, "x,y" point).
The wire `value` is always a string; the sidecar coerces per rule and
refuses anything it can't coerce (`unsupported_input_type`) — it never
guesses. Wrong-kind targets (e.g. StyledText on a Merge) are refused too.

Reason codes: `no_resolve`, `no_clip`, `no_comp`, `missing_path`,
`invalid_path`, `missing_name`, `invalid_index`, `tool_not_allowlisted`,
`tool_not_found`, `unsupported_input_type`, `unsupported`, `resolve_error`.
A Fusion API failure emits a clean result — it never kills the sidecar.

App side: results land in `fusionActionLog`/`lastFusionActionResult`
(rejections of `fusion_*` commands route there, not to the colour log);
the CLI prints `[fusion-action]` lines. The smoke panel is deliberately
NOT wired into the Fusion mode tab — diagnostics only until the polished
surface phase.

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
