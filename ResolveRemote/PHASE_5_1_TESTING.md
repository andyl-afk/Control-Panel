# Phase 5.1 Testing Checklist — Visual Redesign + Settings Tab (UI only)

Prerequisites: Phase 5 working. This phase changed only the iPhone app —
`git diff` for Phase 5.1 must touch nothing under `macOS-helper/`.

- [ ] **New style everywhere.**
  All three tabs render the dark navy palette, vignette background,
  tracked-uppercase labels, and skeuomorphic dials with the right accents:
  Edit purple, Color lime, wheels red/green/blue, temp blue→orange,
  tint magenta, contrast/pivot neutral.

- [ ] **Custom tab bar.**
  EDIT / COLOR / SETTINGS with per-tab active tint (purple/green/white),
  inactive grey, slim surface bar with top hairline.

- [ ] **Edit tab regression.**
  Jog/scrub/shuttle on the big dial, transport, all eight shortcut cards,
  speed slider — everything passes the Phase 1–1.3 checks with the new
  visuals (behaviour identical).

- [ ] **Colour tab regression.**
  Independent simultaneous wheels, knob drags + double-tap resets,
  BEFORE/AFTER hold, Grab Still, per-wheel and Reset All, Looks row
  (refresh, apply flash, empty state, missing-file error) — all pass the
  Phase 3–5 checks.

- [ ] **Indicator lines.**
  Each dial's cap line rotates with adjustment; per-target reset,
  Reset All, and applying a look snap the colour dials' lines back to
  12 o'clock; knob double-tap resets its line.

- [ ] **Settings tab.**
  Connect, Disconnect, Retry, and the error line all work from Settings.
  Auto-connect on launch and on returning to foreground still works.
  Status dots on EDIT and COLOR reflect state (green/orange/red); tapping
  the dot or the gear lands on Settings.

- [ ] **Haptic settings.**
  The master toggle silences all haptics; Light/Medium/Strong tangibly
  changes tick strength (the picker plays a sample bump on change).

- [ ] **One screen per tab.**
  No scrolling on a standard iPhone; touch targets all ≥ 44pt.

- [ ] **No helper/sidecar diff.**
  `git log -p ResolveRemote/macOS-helper` shows no Phase 5.1 changes.
