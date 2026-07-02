# Phase 15 Testing Checklist — Fusion Capability Probe + Fusion Diagnostics

(The user-facing spec called this "Phase 14"; the repo already used 14 for
the colour smoke tests, so docs number it 15.)

The iPad FAIRLIGHT tab is replaced by **FUSION**. This phase proves what
Fusion exposes to scripting — it does NOT build the full Fusion surface.
Only two commands exist: `fusion_probe` (pure introspection) and
`open_fusion_page` (the single mutating action). Comp actions, the tool
grid, parameter knob, XY pad and macros are badged placeholders.

**One-time Xcode step:** add `Views/iPad/iPadFusionModeView.swift` and
`Views/FusionCapabilitiesView.swift` to the iOS target, and remove the
deleted `iPadFairlightModeView.swift` reference, then commit
`project.pbxproj`.

## Probe surfaces

- [ ] 1. Helper launches (menu bar or CLI); iOS app connects.
- [ ] 2. iPad: the top tab bar reads EDIT / COLOR / FUSION / DELIVER —
       no Fairlight tab. FUSION tab is orange when active.
- [ ] 3. iPad Fusion tab → **Probe Fusion** emits one
       `fusion_capability_state`; the summary card fills in.
- [ ] 4. iPhone: Settings → Diagnostics → **Fusion capabilities** →
       Probe Fusion works and shows the grouped feature list.
- [ ] 5. Menu bar: **Probe Fusion Capabilities** updates its one-line
       summary (e.g. "Fusion reachable — 2 comps — page edit").
- [ ] 6. CLI (`swift run ResolveHelper`): probing prints `[fusion]` lines.
- [ ] 7. Reconnecting the app re-delivers the cached fusion state (badges
       gate correctly without re-probing manually).

## Probe honesty per Resolve state

- [ ] 8. **Resolve closed:** `resolve_connected:false`, a clear warning,
       everything `unknown`, comp fields null — no crash.
- [ ] 9. **Resolve open, no project:** warnings say no project; page/product
       filled; comp features `unknown`.
- [ ] 10. **Project + timeline, no clip at playhead:** "No video clip at the
       playhead" warning; comp features `unknown`.
- [ ] 11. **Clip with saved Fusion comps (Edit page):** `comp_count` /
       `comp_names` correct; comp-management features `supported`;
       tool_list/active_tool/add_tool/set_tool_input `unknown` with the
       "only proven while the Fusion page is open" warning; **Resolve's
       page did NOT change** during the probe.
- [ ] 12. **Fusion page open on that clip:** re-probe → `tool_list`
       supported, `tool_count` matches the comp, `active_tool`/`add_tool`
       proven; the page-gate warning is gone.
- [ ] 13. Every probe reply carries the "presence only; the probe never
       invokes them" warning for mutating methods.

## Open Fusion Page (the one wired action)

- [ ] 14. iPad PAGES rail: **FUSION** button (probe supported + connected)
       switches Resolve to the Fusion page; a green ✓ result line shows in
       the Fusion tab. Before a successful probe, the tap only toasts.
- [ ] 15. iPad Fusion tab **Open Fusion Page** tile does the same.
- [ ] 16. iPhone Fusion capabilities sheet: **Open Fusion Page** enabled
       only when supported; result line appears (`ok:true`).
- [ ] 17. With Resolve closed: `ok:false, reason:no_resolve` — clean failure.
- [ ] 18. Other PAGES rail buttons (CUT/EDIT/COLOR/FAIRLIGHT/DELIVER) still
       toast "not wired yet" and send nothing.

## Placeholders stay inert

- [ ] 19. Add/Import/Export/Load/Rename/Delete Comp tiles show their probed
       status badges + NOT WIRED; taps toast locally; the helper log shows
       **nothing sent**. Delete Comp additionally shows DANGEROUS.
- [ ] 20. TOOLS grid, PARAMETER / XY PAD and MACROS panels are badged
       placeholders; taps never reach the helper.
- [ ] 21. Copy JSON (iPhone sheet and iPad settings) puts the raw
       fusion_capability_state line on the clipboard.

## Regressions

- [ ] 22. Capability probe (Settings → Resolve capabilities) still works.
- [ ] 23. Colour smoke tests still work.
- [ ] 24. Colour wheels/knobs, node stepper, bypass, presets, Grab Still
       unchanged.
- [ ] 25. Edit Mode jog/transport/shortcuts still work; iPhone unchanged.
- [ ] 26. iPad settings shows the FUSION (PHASE 15) summary card with
       probe age.
