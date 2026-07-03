# Phase 18 Testing Checklist — Customisable Tool Grid + Expanded Catalog

Follow-up to the Phase 17 hardware pass (all 16 original tool ids proved
good except Planar Tracker — Resolve 21.0.0b refuses to create it via
scripting; it stays listed with a "not scriptable on 21.0b" note in case a
future Resolve fixes it).

The TOOLS grid is now yours to arrange: an **Edit Tools** tile opens a
catalog of ~50 curated Fusion tools grouped by category. No new Swift
files — pull and build.

- [ ] 1. TOOLS grid shows the usual 16 plus a dashed **Edit Tools** tile.
- [ ] 2. Edit Tools opens the picker; categories render (Generators,
       Composite, Transform, Tracking, Masks, Blur/Sharpen,
       Light/Effects, Colour, Keying, Paint/Warp, Time/Optics).
- [ ] 3. Deselect a tool → it leaves the grid immediately. Add one → it
       appears at the end of the grid.
- [ ] 4. Selection survives app relaunch (persisted).
- [ ] 5. Reset returns the default 16.
- [ ] 6. The last remaining tool can't be removed (tap does nothing).
- [ ] 7. Newly added catalog tools actually add in Resolve on tap — try a
       few unverified ones (e.g. Color Curves, Delta Keyer, Corner Pin,
       Fast Noise) and note any that fail with `resolve_error`, same
       drill as Phase 17.
- [ ] 8. Soft Glow gets Gain / Glow Size on the parameter knob (new map
       entry); unmapped tools still say "no mapped parameters".
- [ ] 9. Planar Tracker tile shows its "not scriptable on 21.0b" note and
       fails cleanly if tapped.
- [ ] 10. Knob / XY pad / comp actions / presets all unchanged
       (Phase 17 checklist items 7–25 spot-check).
