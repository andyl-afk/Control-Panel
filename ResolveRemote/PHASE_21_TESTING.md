# Phase 21 Testing Checklist — Production Pass + Fixes

The dev scaffolding is gone from the everyday UI: probes/smoke tests live
behind **Settings → About → Developer diagnostics**; every inert
placeholder control was removed or replaced with a real feature; the PAGES
rail now actually switches Resolve's pages. Plus fixes for the Looks strip
and the colour-page layout. No new Swift files — pull and build.

## If the Edit page is dead (keyboard path)

Colour/Fusion working while Edit does nothing = the Mac's keyboard path,
not the app. Check the menu bar helper:
- [ ] 1. "Accessibility: granted" shows in the menu. If not (unsigned dev
       builds LOSE the grant on every Xcode rebuild): System Settings →
       Privacy & Security → Accessibility → re-enable Resolve Remote
       Helper, relaunch it.
- [ ] 2. "Dry-run mode" toggle is OFF.
- [ ] 3. After fixing, iPad Edit jog/transport/shortcuts drive Resolve.

## Looks (DRX) strip

The sidecar reads **`~/ResolveRemote/Looks`** (it creates the folder on
helper launch — capital L, in your home folder, NOT Documents). A file
named `Moody.drx` becomes a "Moody" chip.
- [ ] 4. Drop a .drx there → the chip appears within ~2 s WITHOUT leaving
       the Colour tab (new: the folder re-lists on the status poll).
- [ ] 5. Tapping the chip applies the look.

## Production cleanup

- [ ] 6. Top bar: EDIT / COLOR / FUSION only (DELIVER tab gone).
- [ ] 7. Bottom bar: Dashboard / Settings (Macros gone).
- [ ] 8. **PAGES rail actually works**: CUT/EDIT/FUSION/COLOR/FAIRLIGHT/
       DELIVER each switch Resolve to that page. SHIFT key gone.
- [ ] 9. Edit tab: custom-shortcut strip gone; wheel/transport/shortcuts
       unchanged.
- [ ] 10. Colour tab: ADJUSTMENTS is five real knobs (inert Balance/Mid
        Detail/Highlight gone); TOOLBOX strip gone; NODE & CLIP row is
        Bypass / Reset Node / Grab Still only (inert tiles + overflow
        gone); LOOKS badge chip gone.
- [ ] 11. Fusion tab: header has Open Fusion Page only (probe runs
        automatically); custom-shortcut strip gone.
- [ ] 12. Healthy controls show NO capability chips anymore; chips only
        appear for unknown/unsupported/dangerous states.
- [ ] 13. Settings: DIAGNOSTICS section hidden by default; About gains a
        "Developer diagnostics" toggle that brings back all four probe/
        smoke-test screens (iPhone) and the probe buttons + raw JSON
        column (iPad).

## Colour-page fixes

- [ ] 14. NODE FX panel: fixed height — applying FX or grades in Resolve
        no longer reflows/resizes the page.
- [ ] 15. The highlighted node card now says **TARGET** (it marks where
        the wheels/knobs land — the stepper moves it; it does not track
        Resolve's own node selection, which the API can't read).
- [ ] 16. Stepping the node moves the TARGET highlight.

## Regressions

- [ ] 17. Wheels, knobs, bypass, presets, stills, node stepper unchanged.
- [ ] 18. Fusion tools/knob/XY/comps/macros unchanged.
- [ ] 19. iPhone tabs unchanged (aside from the hidden diagnostics).
