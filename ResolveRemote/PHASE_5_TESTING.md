# Phase 5 Testing Checklist — Colour Tab Redesign (UI only)

Prerequisites: Phase 4 working. This phase changed only the iPhone app —
`git diff` for Phase 5 must touch nothing under `macOS-helper/`.

- [ ] **Everything fits on one screen.**
  On a standard-size iPhone, all seven sections are visible without
  scrolling: header, three wheels, action row, speed, knobs, looks, tab bar.

- [ ] **Wheels are independent.**
  Turn GAIN: only the gain value (readout and Resolve) changes; LIFT and
  GAMMA stay put. Same for the other two.

- [ ] **Two wheels at once.**
  Touch LIFT and GAIN simultaneously and turn both: both values update
  correctly in Resolve and in the readouts (per-target batching).

- [ ] **Ring indicators.**
  Turning a wheel rotates its accent tick off 12 o'clock in the same
  direction as the finger. The per-wheel reset, Reset All, and applying a
  look all snap the relevant ticks back to 12 o'clock.

- [ ] **Connection header.**
  Default is the slim row (dot, host:port, clip name). Tapping the row
  expands the full panel; Connect works from there and collapses it;
  tapping the dot collapses it. Disconnect works from the expanded state.
  Switch tabs: the header shows the same state on EDIT and COLOUR.

- [ ] **Clip name updates.**
  Move the Resolve playhead to another clip and touch a wheel: the header's
  clip name switches.

- [ ] **Phase 4 behaviours intact.**
  Reset All, hold BEFORE/AFTER, Grab Still, all five knobs (including
  double-tap reset), and the Looks row (refresh, apply, empty state,
  missing-file error) behave exactly as in PHASE_4_TESTING.md.

- [ ] **Edit tab unchanged.**
  EDIT works exactly as before, now with the compact header on top.

- [ ] **No helper/sidecar diff.**
  `git log -p --follow ResolveRemote/macOS-helper` shows no Phase 5 changes.
