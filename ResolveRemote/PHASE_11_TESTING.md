# Phase 11 Testing Checklist — Resolve Capability Probe

Diagnostic feature: the app asks the helper what the installed DaVinci
Resolve 21 Studio actually supports. Nothing in Resolve is changed by a
probe. (Spec called this "Phase 10"; renamed to 11 to avoid clobbering the
haptics checklist in `PHASE_10_TESTING.md`.)

Prerequisites: Phase 9/10 working. New iOS file `CapabilityProbeView.swift`
must be added to the Xcode iOS target (one-time). Rebuild the helper too.

- [ ] **Helper starts** (menu bar or CLI) and accepts connections.
- [ ] **iOS app connects** to the helper.
- [ ] **Capability screen appears**: Settings → DIAGNOSTICS → "Resolve
      capabilities" opens the sheet.
- [ ] **Probe sends**: tapping "Probe Resolve" populates the panel.
- [ ] **Resolve closed** → panel shows `resolve_connected: false`, all
      features `unknown`, nothing crashes.
- [ ] **Resolve open, no project** → partial state (connected true,
      project/timeline/video item false).
- [ ] **Project + timeline open** → project/timeline show `yes`.
- [ ] **Color page + clip selected** → colour/node/still features probe
      as supported (cdl, node_graph, grab_still, apply_drx, set_lut,
      reset_grades).
- [ ] **Missing API functions** → those features show `unsupported`/
      `unknown`; the sidecar never crashes.
- [ ] **Bad sidecar JSON** does not crash helper or app (existing
      newline-JSON tolerance).
- [ ] **Copy JSON** button copies the raw capability payload to the phone
      clipboard.
- [ ] **Existing Edit Mode** jog/transport/shortcut buttons still work.
- [ ] **Existing Colour commands** still route to the sidecar (wheels,
      knobs, trackball, nodes, looks).
- [ ] **CLI** still works in dry-run and send-keys modes; on a probe it
      prints a `[capability]` summary.
- [ ] **Menu bar helper** still launches/accepts connections; "Probe
      Resolve Capabilities" runs a probe and the summary line updates.

## Notes on honesty

- Studio AI features (voice isolation, Magic Mask, Smart Reframe) report
  `unknown` unless a matching scriptable method is actually present — their
  absence from scripting does not prove the feature is missing. They are
  never invoked by the probe.
- The Photo page is reported `unknown` with a warning; the probe never
  switches your page to test it.
