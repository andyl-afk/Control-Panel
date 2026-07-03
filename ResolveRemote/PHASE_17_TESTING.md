# Phase 17 Testing Checklist — Wired Fusion Control Surface

The iPad Fusion tab is now the real mockup surface: the TOOLS grid adds
tools, the SELECTED PARAMETER knob and XY pad drive live inputs, and comps
are managed end-to-end. No new Swift files — after pulling, just build.

**⚠️ Use a disposable clip/comp — tools, comps and parameters really
change.** The four proven tool ids are TextPlus / Background / Merge /
Transform; the other twelve are best-known ids ("id unverified" note on
the tile) — **please record which ones fail** so the allowlist can be
corrected.

## Context + header

- [ ] 1. Fusion tab header shows a green dot + "clip · N comps · page …"
       once a clip with a comp is current (updates within ~2 s).
- [ ] 2. With no clip/comp: header shows the reason; tool tiles and knob
       toast instead of sending (helper log stays silent).
- [ ] 3. Open Fusion Page still works from the header.

## Tools grid (wired)

- [ ] 4. Tap **Text+** → a TextPlus node appears in the comp, the header
       result line shows `✓ fusion_add_tool`, and the SELECTED PARAMETER
       panel switches to the new tool.
- [ ] 5. Tap **Transform** → Transform node added; parameter panel shows
       Size / Angle chips and the XY pad wakes up.
- [ ] 6. Tap all 16 tiles (disposable comp!) and note which return
       `✕ fusion_add_tool (resolve_error)` — expected candidates:
       Planar Tracker, Drop Shadow, Retime, Lens Distort. Report the
       failures.

## Selected parameter knob

- [ ] 7. With a Transform selected: turning the knob on **Size** visibly
       scales the image; the readout tracks the sidecar value.
- [ ] 8. Switch chip to **Angle** → knob rotates the image.
- [ ] 9. FINE / NORMAL / COARSE change the per-tick step (0.25× / 1× / 4×).
- [ ] 10. Fast spins stay smooth (ticks coalesce at ~30 Hz, no flooding).
- [ ] 11. Values pin at the documented clamps (e.g. Size stops at 5.0).
- [ ] 12. RESET (or double-tap the knob) returns the parameter to its
        default.
- [ ] 13. A tool with no mapped params (e.g. Tracker) shows the honest
        "no mapped parameters" message — nothing is sent blind.
- [ ] 14. "Use Active Tool" adopts whatever node is selected in Resolve.

## XY pad

- [ ] 15. Dragging the pad moves the Transform's Center; the puck follows
        the sidecar's value (not the finger directly).
- [ ] 16. Screen up = image up (+y). FINE/COARSE scale the drag.
- [ ] 17. Center clamps at ±0.5 beyond the frame each axis (−0.5…1.5).
- [ ] 18. CENTER button resets to (0.5, 0.5).
- [ ] 19. With a Blur selected the pad disables with the hint text.

## Composition actions + presets

- [ ] 20. Comp chips list the clip's comps; tapping selects (orange).
- [ ] 21. Add Comp creates one; Load Comp opens the selected chip.
- [ ] 22. Rename shows the text alert and renames the selected comp.
- [ ] 23. Export drops an auto-named `.comp` into `~/ResolveRemote/Comps`.
- [ ] 24. Delete shows the destructive dialog naming the comp; confirming
        deletes it; cancelling sends nothing.
- [ ] 25. Drop a `.comp` file into `~/ResolveRemote/Comps` → Refresh →
        chip appears in MACROS / COMP PRESETS → tap imports it (comp
        count grows).

## Regressions

- [ ] 26. Fusion capability probe + Fusion smoke tests (Settings →
        Diagnostics) still work. (Note: smoke-test Export with an empty
        path now auto-names instead of erroring.)
- [ ] 27. Colour wheels/knobs/presets/stills unchanged; Edit mode
        unchanged; iPhone unchanged.
- [ ] 28. CLI still prints `[fusion-action]` lines for one-shot actions;
        knob ticks do NOT spam the log (state lines only).
- [ ] 29. Kill Resolve mid-session: knob/pad/actions fail cleanly with
        reasons; reconnect recovers.
