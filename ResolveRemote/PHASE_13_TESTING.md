# Phase 13 Testing Checklist — iPad Visual Alignment (restyle only)

No new files: `git pull` + rebuild is enough (no Xcode target changes).
No protocol/helper/sidecar changes; all Phase 12 gating rules unchanged.

- [ ] **Build passes** for iPhone and iPad; **iPhone UI is unchanged**.
- [ ] **Top bar**: EDIT / COLOR / FAIRLIGHT / DELIVER tabs (active tab
      filled with its accent), connection dot + label + latency, gear →
      Settings.
- [ ] **Bottom bar**: Dashboard (returns from Settings to the last work
      mode) / Macros (toast: "coming in Phase 14") / Settings.
- [ ] **PAGES rail** on the right of Edit/Colour/Fairlight: CUT…DELIVER
      tiles + SHIFT — every tap toasts "not wired yet" and sends nothing;
      the rail shows the `open_page` capability badge once.
- [ ] **Deliver tab** is an honest placeholder (text + Not-wired badge).
- [ ] **Edit**: speed shows a **%**, pills sit **below** the wheel,
      transport has **labels** with a **green PLAY/PAUSE**, shortcuts in a
      panel card, numbered CUSTOM SHORTCUTS strip toasts.
- [ ] **Colour**: PRIMARY panel with LIFT/GAMMA/GAIN selector (SAT is a
      knob, still wired), wheel has the **colour-sweep ring + green dot**,
      circular reset sits beside the wheel and still resets the visible
      target.
- [ ] **ADJUSTMENTS** is a 2×4 all-knob grid: Contrast/Pivot/Saturation/
      Temp/Tint turn and reset as before; **Balance/Mid Detail/Highlight**
      are knob-shaped but inert — tapping toasts ("drag the wheel cap" /
      "no scripting API") and nothing is sent.
- [ ] **NODE & CLIP**: stepper still steps nodes; **Bypass Grade** tile
      hold-compares (wired); **Reset Node** resets app trims (wired);
      Prev/Next Clip + Add Node toast; **"…"** expands the overflow row
      with Grab Still (wired), Set LUT, Magic Mask, Smart Reframe, and
      Reset Grade (Dangerous, inert).
- [ ] **TOOLBOX** chips + LOOKS strip: chips toast; looks still apply.
- [ ] **Fairlight**: labelled transport + Add Marker work; track/marker
      placeholders badge correctly; **no mixer** (deliberate — the API has
      no live audio state).
- [ ] **Settings**: three columns; SHORTCUT LAYOUT + GENERAL cards say
      "Phase 14" with Not-wired badges; Probe / Copy JSON / Full Feature
      List still work; raw JSON shows in the third column.
- [ ] **Gating regression**: with no probe, advanced controls sit at
      Experimental/disabled; after a probe they match the capability
      state; blocked taps only ever toast. Helper disconnect / Resolve
      closed → no crashes.
