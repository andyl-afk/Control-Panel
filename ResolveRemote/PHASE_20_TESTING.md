# Phase 20 Testing Checklist — Expanded Parameter / XY Coverage

Follow-up to the Phase 18 hardware pass: every catalog tool verified except
**Planar Tracker and Planar Transform** (Resolve 21.0.0b refuses to create
the planar tools via scripting — both stay listed and flagged). The dead
knob/XY on new tools was the curated map only covering 8 tool types; this
phase expands it to ~20 (params) and 9 (XY).

The safety rule is unchanged: a mapped input whose GetInput doesn't return
a number is refused — a wrong id means a dead knob and a "?" readout,
never a blind set. **Note which params show "?" or don't respond** so the
ids can be corrected. No new Swift files — pull and build.

New parameter coverage (knob):

- [ ] 1. Fast Noise: Detail / Contrast / Brightness / Scale.
- [ ] 2. Dissolve: Mix.
- [ ] 3. Transform gains Aspect; Merge gains Angle; Blur gains Blend.
- [ ] 4. DVE: Z Move.
- [ ] 5. Rectangle/Ellipse masks: Level / Soft Edge / Width / Height.
- [ ] 6. Triangle / Polygon / B-Spline / Wand masks: Level / Soft Edge.
- [ ] 7. Directional Blur: Length / Angle.
- [ ] 8. Defocus: Defocus Size. Sharpen: Amount.
- [ ] 9. Drop Shadow: Softness.
- [ ] 10. Color Corrector gains Gamma + Saturation.
- [ ] 11. Brightness/Contrast: Gain / Gamma / Brightness / Contrast /
        Saturation.
- [ ] 12. Matte Control: Matte Blur.
- [ ] 13. Retime: Speed (negative plays backwards — clamped ±4×).

New XY pad coverage:

- [ ] 14. DVE, Rectangle / Ellipse / Polygon / B-Spline masks: pad moves
        their Center.
- [ ] 15. Drop Shadow: pad moves the shadow offset (different input id
        under the hood — should just work).

Still honestly unmapped (knob says "no mapped parameters"): Text 3D,
Resize, Crop, Letterbox, Camera Shake, trackers, Highlight, Color/Hue
Curves, Color Gain, White Balance, Channel Booleans, Gamut, keyers (except
Matte Control), Paint, Grid Warp, Displace, Corner Pin, Time Stretcher,
Lens Distort, Film Grain — curve/point/enum-driven tools without a safe
single scalar, or ids not yet verified.

- [ ] 16. Planar Tracker AND Planar Transform tiles both show "not
        scriptable on 21.0b" and fail cleanly if tapped.
- [ ] 17. Unverified badges are gone from every other catalog tool.
- [ ] 18. Phase 17 basics still pass (Transform Size/Angle knob, Text+
        Center XY, comp actions, presets).
