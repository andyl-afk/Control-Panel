# Phase 22 Testing Checklist — Tri-Wheel Primary Panel + Fluted Wheel Face

The iPad Colour tab now shows LIFT / GAMMA / GAIN as three grading wheels
side by side (no more selector), drawn as the matte-black machined wheel
from the product photo: recessed well with a bottom rim light, fine fluted
grip ring, big domed cap with a drilled-dimple indicator, deep soft
shadows. Same gestures and commands as before. No new Swift files.

- [ ] 1. Colour tab: PRIMARY spans the top with three wheels — LIFT,
       GAMMA, GAIN — each with its own value readout and small reset.
- [ ] 2. The wheel face matches the photo: monochrome black, fluted ring,
       dimple indicator (no colour-sweep ring). The dimple rotates with
       the master value; the accent colour appears only on the balance
       puck.
- [ ] 3. Each wheel: outer-ring drag = master (lift/gamma/gain level);
       cap drag = colour balance trackball; two-finger rotate = master;
       double-tap cap = balance reset; double-tap ring = nothing sent
       when not live.
- [ ] 4. Small circular reset (top-right of each wheel) resets that
       wheel's master + balance.
- [ ] 5. The speed chip (0.5x/1x/2x) sits top-right of the panel and
       scales all three wheels + the knobs.
- [ ] 6. Grading on one wheel doesn't disturb the others; pucks track the
       sidecar state (bypass/compare still works).
- [ ] 7. With Resolve/colour unavailable: ONE gate card over the wheel
       row (not three), wheels dimmed, nothing sent.
- [ ] 8. Second row: ADJUSTMENTS (5 knobs) left, NODE & CLIP + NODE FX
       right; LOOKS strip along the bottom — no layout jumping.
- [ ] 9. Everything fits without scrolling on a landscape iPad.
- [ ] 10. iPhone colour tab unchanged (still the paged single dial).
