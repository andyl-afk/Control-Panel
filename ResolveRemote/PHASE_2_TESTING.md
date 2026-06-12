# Phase 2 Testing Checklist — Colour Mode

Prerequisites: DaVinci Resolve **Studio** with External scripting = Local
(Preferences → System → General), python3 installed, Phase 1 working.

- [ ] **Helper starts, sidecar launches.**
  `swift run ResolveHelper` — console shows `[sidecar] started (pid …)` and
  `[sidecar] resolve_bridge started`, then either `connected to Resolve` or
  a clear not-reachable reason.

- [ ] **Colour tab shows available with a clip name.**
  With Resolve Studio open, a timeline active and the playhead on a clip:
  switch to the COLOUR tab — controls are live and "Clip: <name>" appears.

- [ ] **GAIN wheel works.**
  Select GAIN, turn the wheel: the clip visibly brightens (right) / darkens
  (left) in Resolve and the GAIN readout changes accordingly.

- [ ] **GAMMA inversion is correct.**
  Select GAMMA, wheel right: midtones get *brighter* (the readout — CDL
  Power — goes *down*; that's the documented inversion).

- [ ] **LIFT adjusts shadows.**
  Select LIFT, wheel right: shadows lift; readout moves from 0.000.

- [ ] **Saturation slider works.**
  Drag the detent strip right/left: saturation visibly increases/decreases
  with a tick haptic per detent, SAT readout tracks.

- [ ] **Resets work.**
  Each per-row reset returns that value to its default (0.000 lift,
  1.000 gamma/gain/sat) visually and in the readout; Reset All returns all
  four at once. Heavy haptic on each reset.

- [ ] **Clip switching.**
  Move the Resolve playhead to a different clip, touch the wheel: the new
  clip is affected, the clip name and readouts switch to that clip's state
  (defaults if untouched so far).

- [ ] **Fast wheel spin stays smooth.**
  Spin hard: the grade tracks without lag piling up after release (SetCDL
  is rate-limited to 30/s with summed deltas).

- [ ] **Quit Resolve → graceful unavailable → recover.**
  Quit Resolve with the app connected: the next wheel move / Retry flips
  the Colour tab to "Colour unavailable" with a sensible reason. Reopen
  Resolve (timeline active) and tap Retry: controls come back.

- [ ] **Scripting-disabled reason is human-readable.**
  Set External scripting to None (or use the free version): the reason
  mentions Resolve Studio and the External scripting preference.

- [ ] **Edit Mode unchanged.**
  The EDIT tab still passes the Phase 1 checklist (PHASE_1_TESTING.md).
