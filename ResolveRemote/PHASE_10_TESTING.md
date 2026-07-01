# Phase 10 Testing Checklist — Feel Like Hardware

Prerequisites: Phase 9 working. Test on a **real iPhone** (Core Haptics
does nothing in the Simulator — the app falls back to the old generators
there, which is itself worth confirming doesn't crash).

## Core Haptics feel

- [ ] **Detent clicks feel sharp and mechanical.**
  Spinning any wheel gives crisp, light clicks (distinct from a button
  press) — not the old dull thud.

- [ ] **Buttons vs detents vs resets are distinct.**
  A transport/shortcut button tap, a wheel detent, and a reset (heavy
  bump) each feel clearly different.

- [ ] **Direction change is a softer, heavier thunk.**
  Reverse the jog wheel mid-spin — the reversal feels different from a
  normal detent.

## Wheel texture (the marquee feature)

- [ ] **Spinning feels like a weighted wheel.**
  Drag the Edit jog wheel or a Colour wheel: under the detent clicks there
  is a continuous rumble that gets **stronger the faster you spin** and
  fades as you slow/stop. Lifting your finger ends it cleanly.

- [ ] **Only the big wheels have texture.**
  The five small Colour knobs and the trackball give discrete ticks only —
  no continuous rumble.

- [ ] **Texture toggle works.**
  Settings → Haptics → turn off "Wheel texture": detent clicks remain but
  the continuous rumble is gone. Turn the master Haptics toggle off:
  everything goes silent.

- [ ] **Intensity setting scales everything.**
  Light / Medium / Strong noticeably changes both clicks and texture
  strength (the picker plays a sample on change).

- [ ] **Survives backgrounding.**
  Background the app and return — haptics still fire (the engine restarts
  on foreground).

## Latency / heartbeat

- [ ] **Latency shows in Settings.**
  While connected, Settings → Connection shows a live "NN ms" that updates
  every ~2.5 s (green under 40 ms, amber under 120, red beyond).

- [ ] **Dead-link detection.**
  With the phone connected, quit the helper app on the Mac (don't just
  close the menu). Within ~10 s the phone notices (no pongs) and flips to
  Reconnecting → then Disconnected/Retry — it doesn't sit falsely
  "Connected".

- [ ] **Reconnect still works.**
  Restart the helper (or tap a discovered Mac / Retry) → green again,
  latency resumes.

## Regression

- [ ] All Phase 1–9 behaviour still passes: Edit, Colour wheels +
  trackball + knobs + nodes + Looks, Settings connect/auto-connect,
  Bonjour discovery, menu bar helper.
