# Resolve Remote

An iPhone haptic controller for DaVinci Resolve: jog/shuttle editing, colour
wheels with a trackball, knobs, look presets — over your local network.

## Quick start (≈2 minutes, no Terminal)

1. **On the Mac:** install and open **Resolve Remote Helper**. It lives in
   the menu bar (dial icon) — no window, no Dock icon.
2. When asked, grant **Accessibility** access (System Settings → Privacy &
   Security → Accessibility → enable Resolve Remote Helper). This is what
   lets the app press keys for you. The menu bar item has a shortcut to the
   right pane if you skipped the prompt.
3. Optionally turn on **Launch at Login** from the menu bar item.
4. **On the iPhone:** open Resolve Remote, go to **Settings** (gear tab),
   and tap your Mac under **NEARBY MACS**. Allow local-network access when
   iOS asks. That's it — the dot turns green.

The phone remembers your Mac and reconnects automatically next time.

## Requirements

- macOS 13 or later.
- iPhone and Mac on the **same network** (a Personal Hotspot or USB-C
  tethering also works).
- **Edit Mode** works with any DaVinci Resolve.
- **Colour Mode** needs **DaVinci Resolve Studio** with
  Preferences → System → General → *External scripting using* set to
  **Local** (the free version doesn't expose the scripting API), and
  python3 on the Mac (macOS prompts to install it if missing).

## Using it

- **EDIT tab** — jog/shuttle/scrub wheel, transport, and shortcut keys
  (blade, ripple delete, marker, in/out, prev/next edit, undo). Keys go
  straight to Resolve, even when it's not the frontmost app.
- **COLOR tab** — one grading wheel paged across LIFT / GAMMA / GAIN
  (swipe beside the wheel or tap the labels). The wheel ring sets the
  level; the centre cap is a **trackball** for colour balance; two-finger
  rotate also sets the level. CONTRAST / PIVOT / SAT / TEMP / TINT knobs
  (drag up/down, double-tap to reset), hold **BEFORE/AFTER** to compare,
  camera button grabs a still, and the **node stepper** picks which node
  your trims land on.
- **LOOKS** — export grades from Resolve's Gallery as `.drx` files into
  `~/ResolveRemote/Looks/` on the Mac; they appear as one-tap presets on
  the phone. The filename is the button name. A look can contain anything
  Resolve can grade — curves, windows, multiple nodes.

### Good to know

- **Node selection:** the stepper controls where grades land, but
  Resolve's *highlighted* node on screen won't follow — the scripting API
  can't move it. Build your node tree in Resolve first (e.g. 1 balance,
  2 look, 3 vignette), then trim each stage from the phone.
- **Existing grades:** the API can't read CDL values back, so the first
  wheel move on a clip/node the app hasn't touched overwrites that node's
  CDL with the app's own values. Use Resolve's undo if it bites you.
- **Manual connection fallback:** if discovery doesn't work on your
  network, the helper's menu bar item shows the Mac's IP — enter it under
  Settings → CONNECTION on the phone.
- **Capabilities:** Settings → Diagnostics → Resolve capabilities runs a
  probe that reports whether your installed Resolve Studio exposes each
  feature (colour, stills, LUTs, markers, etc.) — handy when something
  isn't behaving.

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| Mac doesn't appear under Nearby Macs | Same Wi-Fi network? Helper running (menu bar icon)? iOS Settings → Privacy & Security → Local Network → Resolve Remote enabled? Use the manual IP fallback if your network blocks Bonjour. |
| Connects, but keys don't reach Resolve | Accessibility not granted (menu bar item → Grant Accessibility Access…), or Dry-run mode is on in the menu. |
| Colour tab says unavailable | Resolve Studio running? External scripting = Local? A timeline open with the playhead on a clip? The message states the exact reason. |
| "Listener failed" / Stopped in the menu | Another copy of the helper is already running — quit one. |

## For developers

Building from source, the CLI helper, protocol details, and distribution
notes (signing/notarization, TestFlight) are in [DEVELOPMENT.md](DEVELOPMENT.md).
Per-phase test checklists are in `PHASE_*_TESTING.md`.
