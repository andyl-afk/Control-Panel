# Phase 12 Testing Checklist — iPad Control Surface Shell + Capability Gating

One-time Xcode setup: enable **iPad** under the iOS target's Supported
Destinations, drag the new **`Views/iPad/` folder** into the target
(reference, don't copy), then commit `project.pbxproj`. Rebuild the helper
too (it gained the capability re-broadcast on client connect).

- [ ] **1. App builds** for both iPhone and iPad destinations.
- [ ] **2. iPhone layout still works** — tabs, jog wheel, colour dial,
      haptics all unchanged (idiom switch only activates on iPad).
- [ ] **3. iPad opens the new dashboard** — page rail (Edit / Color /
      Fairlight / Settings), status strip, dark control-surface look.
- [ ] **4. Status strip shows helper connection** (dot + label), and
      latency once connected.
- [ ] **5. After a probe** (automatic on connect, or Settings → Probe) the
      strip shows Resolve product/version, current page, PROJ/TL/CLIP
      marks, and a live "probed … ago" age.
- [ ] **6. iPad Edit Mode** shows the big dial, mode pills, speed,
      transport, and the shortcut grid.
- [ ] **7. Edit buttons send existing commands** — verify in the helper
      log / Resolve (jog, play/pause, marker, etc.).
- [ ] **8. iPad Colour Mode** shows the primary wheel with target selector
      (LIFT/GAMMA/GAIN/SAT), knob grid, node stepper, looks strip, action
      grid, toolbox row.
- [ ] **9. No capability state** (fresh connect to a helper that never
      probed, before auto-probe lands): wheel shows "CDL unknown",
      advanced tiles show Experimental/Not wired, nothing executes.
- [ ] **10. With the real Resolve 21 Studio probe**: CDL wheel + knobs go
      live; Grab Still, node stepper, looks, Reset Trims work; Set LUT /
      Reset Grade / Magic Mask / Smart Reframe show **Supported** badges.
- [ ] **11. Unknown controls** (Voice Isolation) show Experimental;
      unwired ones (pages, prev/next clip, toolbox, Mid Detail/Highlight)
      show Not wired.
- [ ] **12. Reset Grade** is visible with Supported + Dangerous + Not
      wired badges and does nothing but a local toast.
- [ ] **13. Magic Mask** — visible, badge only, never executes.
- [ ] **14. Smart Reframe** — visible, badge only, never executes.
- [ ] **15. Voice Isolation** shows unknown/Experimental (per the real
      probe result).
- [ ] **16. No Photo mode** appears anywhere on the rail.
- [ ] **17. Settings/Diagnostics** (iPad) shows the summary card,
      warnings, probe age, and the raw JSON.
- [ ] **18. Capability Probe still works** — Probe button refreshes the
      summary; Copy JSON fills the clipboard; Full Feature List opens the
      existing CapabilityProbeView.
- [ ] **19. Helper disconnect** while the dashboard is open: status strip
      goes red/reconnecting, no crash; reconnecting re-broadcasts the
      cached capability state (strip repopulates without a manual probe).
- [ ] **20. Resolve closed**: probe shows "Resolve: not connected", wheel
      gates, no crash anywhere.
- [ ] **21. iPhone haptics/jog behaviour unchanged** — spot-check
      PHASE_10_TESTING.md items on the phone.

## Honesty notes

- **Temp/Tint knobs** are labelled "CDL approx": the scripting API has no
  native Temp/Tint, so they skew the CDL Slope channels (you'll see the
  Gain wheel move in Resolve — expected).
- **Reset Trims** (safe, wired — resets this app's CDL trims) is distinct
  from **Reset Grade** (Resolve's ResetAllGrades — dangerous, not wired).
- **Balance** is 2D and lives on the wheel cap trackball, not a knob.
- Not-wired taps only show a local toast in the status strip; they never
  send guessed commands to the helper.
