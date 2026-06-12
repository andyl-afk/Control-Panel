# Phase 3 Testing Checklist — Derived Knobs + Compare

Prerequisites: Phase 2 working (Resolve Studio, scripting Local, python3).

- [ ] **Temp knob direction.**
  Drag TEMP up: the image visibly warms (more red, less blue). Down: cools.
  Readout under the knob tracks (−1.00 … 1.00).

- [ ] **Tint knob direction.**
  Drag TINT up: image shifts green. Down: shifts magenta. Readout tracks.

- [ ] **Contrast pivots around pivot.**
  Raise CONTRAST: image steepens around mid-grey; lower it: flattens. Then
  raise PIVOT noticeably and re-test contrast — the anchor point of the
  steepening has visibly moved (darker pivot = highlights move more, etc.).

- [ ] **Per-knob double-tap reset.**
  Adjust several knobs, double-tap one: only that parameter returns to its
  default (contrast 1.00, pivot 0.435, sat 1.00, temp/tint 0.00), heavy
  haptic fires, image updates.

- [ ] **Reset All resets all eight.**
  Adjust masters and knobs, tap Reset All: image returns to ungraded and
  every readout (lift/gamma/gain rows + all five knob labels) shows its
  default.

- [ ] **Hold BEFORE/AFTER.**
  Grade a clip, press and hold the button: the image reverts to ungraded
  (node 1 bypassed) with a heavy haptic; release: grade returns, second
  heavy haptic. Wheel input while held re-enables the node automatically.

- [ ] **Kill the app mid-hold: no stuck bypass.**
  Hold BEFORE/AFTER and swipe the app away (or toggle Wi-Fi off). The
  helper logs the disconnect and the sidecar re-enables node 1 — the grade
  comes back in Resolve on its own.

- [ ] **Masters still compose correctly.**
  Set contrast ≠ 1, then adjust LIFT/GAMMA/GAIN with the wheel: behaviour
  stays sensible (masters feed into the contrast/pivot composition, so a
  lift change is also contrast-scaled — that's the specified order).

- [ ] **Grades persist across project close/reopen.**
  Grade, close and reopen the project in Resolve: the clip still looks
  graded (CDL lives in the project; the app's shadow state still applies
  on the next wheel touch).

- [ ] **Phase 2 regression.**
  Availability/unavailability, clip switching readouts, and fast-spin rate
  limiting all still pass (PHASE_2_TESTING.md).

- [ ] **Edit Mode unchanged.**
  The EDIT tab still passes PHASE_1_TESTING.md.
