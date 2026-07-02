# Phase 14 Testing Checklist — Colour Action Smoke Tests

(The user-facing spec called this "Phase 13"; the repo already used 13 for
the iPad visual pass, so docs number it 14. Custom shortcuts move to 15.)

Panel: Settings → Diagnostics → **Colour smoke tests**. The nudge / context /
still buttons deliberately exercise the REAL production commands; the new
guarded commands are `reset_grade`, `set_lut`, `apply_drx`.

**⚠️ Test on a duplicate/disposable clip — Reset Grade runs Resolve's real
ResetAllGrades on the current clip.**

- [ ] 1. Helper launches (menu bar or CLI).
- [ ] 2. iOS app connects.
- [ ] 3. Capability Probe still works (Settings → Resolve capabilities).
- [ ] 4. Colour Smoke Test panel opens; status card shows helper/Resolve/
       context lines.
- [ ] 5. **Resolve closed:** every action returns a clean failure
       (`no_color_context` / context line shows the reason) — no crashes.
- [ ] 6. **Resolve open, no project:** same clean failures.
- [ ] 7. **Project/timeline, no current clip:** clip actions fail cleanly.
- [ ] 8. **Color page + disposable clip:** Check Context shows
       "available (clip · node x/y)".
- [ ] 9–12. Lift / Gamma / Gain / Sat nudges succeed — readouts move by the
       tiny documented amounts (±0.004 lift, ±0.010 others) and the grade
       visibly changes. (These are the wheels' own commands.)
- [ ] 13. Grab Still succeeds (still appears in the Gallery, haptic fires).
- [ ] 14. **Test Rejection** button (reset_grade without confirm) returns
       `command_rejected: confirmation_required` in the log — orange dot.
- [ ] 15. **Reset Grade (guarded)** asks for confirmation; confirming runs
       ResetAllGrades, the clip's grade clears, readouts/trims zero out,
       and the log shows ok:true.
- [ ] 16. Set LUT with an empty path → `missing_path` error in the log.
- [ ] 17. Apply DRX with an empty path → `missing_path` error.
- [ ] 18. Set LUT with a valid .cube path → ok:true (LUT visible on the
       active node) or a clear `resolve_rejected`/`resolve_error`.
- [ ] 19. Apply DRX with a valid .drx path → ok:true (grade applied, trims
       purged) or a clear error. Nonexistent path → `invalid_path`.
- [ ] 20. Magic Mask shows status only (from the probe); nothing executes.
- [ ] 21. Smart Reframe shows status only; nothing executes.
- [ ] 22. Malformed sidecar JSON is ignored (existing tolerance) — no
       crashes anywhere.
- [ ] 23. Edit Mode jog/transport/shortcuts still work.
- [ ] 24. iPhone haptics still work.
- [ ] 25. iPad dashboard still builds and runs.
- [ ] 26. Copy Result JSON puts the last raw result line on the clipboard.
