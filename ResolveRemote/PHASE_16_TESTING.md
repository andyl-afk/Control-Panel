# Phase 16 Testing Checklist — Fusion Action Smoke Tests

(The user-facing spec called this "Phase 15"; the repo already used 15 for
the Fusion capability probe, so docs number it 16.)

Panel: Settings → Diagnostics → **Fusion smoke tests**. This proves the
methods the Phase-15 probe found actually execute. Mutating actions need a
confirmation dialog; add-tool/set-input are allowlisted (TextPlus /
Background / Merge / Transform; StyledText / Size / Center); Delete Comp is
status-only.

**⚠️ Test on a duplicate/disposable clip and comp — Add Comp, Import,
Rename, Add Tool and Set Input really mutate the clip's Fusion state.**

**One-time Xcode step:** add `Views/FusionSmokeTestView.swift` to the iOS
target, then commit `project.pbxproj`.

## Regressions first

- [ ] 1. Helper launches (menu bar or CLI); iOS app connects.
- [ ] 2. Resolve Capability Probe still works.
- [ ] 3. Fusion Capability Probe still works (iPad tab + iPhone sheet).
- [ ] 4. Edit controls (jog/transport/shortcuts) still work.
- [ ] 5. Colour diagnostics (smoke tests, wheels, presets) still work.
- [ ] 6. Fusion Smoke Tests panel opens.

## Clean failures in every degraded state

- [ ] 7. **Resolve closed:** every Fusion action fails cleanly
       (`no_resolve` + a readable message) — no crashes.
- [ ] 8. **Resolve open, no project:** clean failures (`no_clip` path,
       message says no project).
- [ ] 9. **Project, no timeline:** clean failures.
- [ ] 10. **Timeline, no clip at playhead:** context reports it; clip
        actions fail with `no_clip`.
- [ ] 11. **Clip with no Fusion comp:** List Tools / tool actions report
        `no_comp` cleanly; List Comps reports 0.

## Read-only actions (clip with a simple Fusion comp)

- [ ] 12. Check Fusion Context → ok:true with page/comp/tool details.
- [ ] 13. List Comps → correct count + names.
- [ ] 14. List Tools → correct tool count and readable name/type entries
        (e.g. MediaIn / MediaOut / Text+).
- [ ] 15. Active Tool → the selected tool, or a clean "none selected"
        (ok:true) with nothing selected.
- [ ] 16. Delete Comp Status → reports availability; comp list unchanged
        (NOTHING deleted).

## Export / import (explicit paths)

- [ ] 17. Export Comp with an empty path → `missing_path`.
- [ ] 18. Export Comp to a folder that doesn't exist → `invalid_path`.
- [ ] 19. Export Comp to a valid path → ok:true and the .comp file exists
        (or a clear `resolve_error`).
- [ ] 20. Import Comp without confirming → `command_rejected:
        confirmation_required` (orange dot in the log).
- [ ] 21. Import Comp with a missing/nonexistent path → `missing_path` /
        `invalid_path`.
- [ ] 22. Import Comp (confirmed, valid file) → ok:true, comp count grew.

## Comp mutations (guarded)

- [ ] 23. Add Comp without confirm ("Test Rejection" button) →
        `command_rejected: confirmation_required`.
- [ ] 24. Add Comp (confirmed) → ok:true, new comp visible in Resolve.
- [ ] 25. Rename Comp without confirm → rejected.
- [ ] 26. Rename Comp with a bad index or empty name → `invalid_index` /
        `missing_name`.
- [ ] 27. Rename Comp (confirmed, valid) → ok:true, name changes in
        Resolve's comp list.

## Tool tests (allowlisted + guarded)

- [ ] 28. Add Text+ Tool without confirm → rejected.
- [ ] 29. Add Text+ Tool (confirmed) → ok:true, TextPlus node appears in
        the comp (or clear API failure).
- [ ] 30. Add Background Tool (confirmed) → same.
- [ ] 31. Set Input: StyledText on the Text+ tool with a test string →
        ok:true and the text visibly changes in the viewer.
- [ ] 32. Set Input with a non-allowlisted input (e.g. Blend) →
        `unsupported_input_type`, nothing set.
- [ ] 33. Set Input Size with a non-number → `unsupported_input_type`.
- [ ] 34. Set Input on a nonexistent tool name → `tool_not_found`.

## Wrap-up

- [ ] 35. CLI prints one `[fusion-action]` line per outcome.
- [ ] 36. Copy Result JSON puts the last raw fusion_action_result on the
        clipboard.
- [ ] 37. Fusion rejections appear in the Fusion result log (not the colour
        smoke-test log).
- [ ] 38. Malformed sidecar JSON is ignored — no crashes anywhere.
