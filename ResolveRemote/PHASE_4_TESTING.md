# Phase 4 Testing Checklist — Looks + Grab Still

Prerequisites: Phase 3 working. The sidecar creates `~/ResolveRemote/Looks/`
on startup (check the `[sidecar]` log line).

- [ ] **Empty folder shows the empty-state chip.**
  With no `.drx` files in the folder, the LOOKS row shows a single dimmed
  chip reading "Drop .drx files in ~/ResolveRemote/Looks".

- [ ] **Presets appear alphabetically after refresh.**
  Export two stills as `.drx` into the folder (see README "Looks"), tap the
  refresh icon: two chips appear, alphabetically ordered, named after the
  files.

- [ ] **Tapping a preset applies the look and zeroes the trim.**
  Tap a chip: the clip visibly takes the look in Resolve, the chip flashes
  green with a heavy haptic, and every readout (masters + knobs) snaps to
  defaults.

- [ ] **Wheel/knobs trim on top of the look.**
  After applying a preset, turn the wheel and a knob: the image keeps the
  look and the trim rides on top (look + trim, not look replaced).

- [ ] **Second preset replaces the first.**
  Apply a different chip: the new look replaces the old one and the trim
  readouts reset to defaults again.

- [ ] **No crash after preset → bypass → wheel.**
  Apply a preset, immediately hold BEFORE/AFTER, release, then turn the
  wheel. Resolve stays alive (this exercises the graph re-fetch workaround
  for the macOS ApplyGradeFromDRX bug).

- [ ] **Deleted file handled gracefully.**
  Delete one `.drx` while its chip is showing, tap the chip: a brief
  "Preset file not found — refresh the list" message appears, nothing
  crashes; tapping refresh removes the chip.

- [ ] **Grab Still works.**
  Tap the camera button: a new still appears in Resolve's Gallery and the
  phone gives a heavy haptic.

- [ ] **Phase 3 regression.**
  Knobs, resets, compare, and disconnect-safety still pass
  (PHASE_3_TESTING.md).
