# Phase 6 Testing Checklist — Premium Dial Pass + Paged Colour Layout (UI only)

Prerequisites: Phase 5.1 working. This phase changed only the iPhone app —
`git diff` for Phase 6 must touch nothing under `macOS-helper/`.

- [ ] **Edit tab fills the screen.**
  No dead bands above or below; the wheel is visibly larger (~80% width)
  and absorbs the spare height; mode pills, speed, transport, and all
  eight shortcuts remain reachable.

- [ ] **Dials read as 3D at all sizes.**
  Big Edit wheel, big Colour dial, and the five small knobs all show the
  machined look: brushed bezel, groove behind the ticks, longer cardinal
  ticks, glowing accent ring, specular cap with deep shadow, and a faint
  accent wash behind the primary dial.

- [ ] **Touched dial "wakes".**
  Touch any dial: the accent ring and glow brighten subtly; release
  returns it. No flashing.

- [ ] **Indicator glow.**
  The cap line is plain white at default and gains a subtle accent glow
  once the value is off-neutral; resets return it to white at 12 o'clock.

- [ ] **Pager: deliberate flick changes target.**
  A straight horizontal flick anywhere on the dial area switches
  LIFT → GAMMA → GAIN (and back) with a directionChange haptic and an
  animated accent change.

- [ ] **Pager: grading never changes the page.**
  Grade vigorously in circles — including fast spins that pass over the
  top of the dial — for a minute. The page must never change.

- [ ] **Segmented labels always switch.**
  Tapping LIFT/GAMMA/GAIN always changes the page, regardless of what
  the dial is doing.

- [ ] **Accent + readout follow the page.**
  The large readout shows the visible target's value; its reset button
  resets only that target.

- [ ] **Layout order.**
  Header, pager row (+ speed badge), big dial, readout, knob row, Looks
  row, action row pinned at the bottom above the tab bar — all on one
  screen, no scrolling.

- [ ] **Speed badge.**
  Tapping cycles 0.5x → 1.0x → 2.0x and visibly changes how far one dial
  rotation moves values — wheel and knobs both.

- [ ] **Full regression.**
  Phase 1–5.1 checklists pass: Edit jog/shuttle/scrub + transport +
  shortcuts, knobs + double-tap reset, BEFORE/AFTER, Grab Still, resets,
  Looks, Settings connect/auto-connect, haptic settings.

- [ ] **No helper/sidecar diff.**
  `git log -p ResolveRemote/macOS-helper` shows no Phase 6 changes.
