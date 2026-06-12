# Phase 7 Testing Checklist — Trackball Colour Balance

Prerequisites: Phase 6 working, Resolve Studio with a timeline open and the
vectorscope visible (Color page → Scopes → Vectorscope).

- [ ] **LIFT balance direction.**
  Select LIFT, drag the cap straight up: shadows push toward red on the
  vectorscope. Drag toward bottom-left: green-ish. The vectorscope trace
  moves the same direction as the finger (red at top, axes 120° apart).

- [ ] **GAIN and GAMMA balance.**
  Same directional behaviour in their ranges (highlights for GAIN, mids
  for GAMMA). Gamma is direction-correct on screen — cap up = red mids,
  not inverted.

- [ ] **Level-neutral hue shifts.**
  A pure balance move barely changes overall brightness (the zero-sum
  weight invariant) — check the waveform stays roughly put while the
  vectorscope moves.

- [ ] **Puck tracks state per clip.**
  The puck follows the drag, sits where the sidecar applied it, and
  persists when you switch clips and back (each clip keeps its own puck
  positions, swapping with the shadow state).

- [ ] **Cap vs ring vs two-finger.**
  A drag starting on the cap never moves the master; a drag starting on
  the ring never moves the balance. Two-finger rotation anywhere on the
  dial adjusts the master while the puck stays put; single-finger input
  is suspended while two fingers are down.

- [ ] **Page swipe containment.**
  Page changes only happen from horizontal swipes OUTSIDE the dial circle
  (the margins beside it) or the segmented labels — never from cap or
  ring gestures.

- [ ] **Reset semantics.**
  Double-tap the cap: balance returns to centre, master value untouched,
  heavy haptic. The reset button under the dial: master AND balance for
  that target. Reset All: all eight params and all three balances.
  Readouts and pucks snap accordingly.

- [ ] **Magnitude clamp.**
  Keep dragging past full deflection: the puck stops at the rim
  (magnitude 1.0) with a heavyBump, values don't run away; wheelTick
  fires at each 0.1 ring on the way out.

- [ ] **Composition order.**
  Balance + temp/tint/contrast together compose sensibly (balance is
  applied to the masters before temp/tint/contrast, so contrast scales a
  balanced offset — same convention as the masters).

- [ ] **Persistence.**
  Grade with balance, close and reopen the project: the look (including
  balance) is still on the clip.

- [ ] **Full regression.**
  Phase 1–6 checklists pass; Edit wheel and the five small knobs are
  completely unchanged.
