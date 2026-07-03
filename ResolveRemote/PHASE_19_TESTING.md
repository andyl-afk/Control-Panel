# Phase 19 Testing Checklist — Node FX Inventory (GetToolsInNode)

Read-only: the Colour tab's new **NODE FX** panel shows, per Color-page
node, its label and the ResolveFX/tools inside it (Color Space Transform,
Film Look Creator, Lens Blur, Film Grain, …). Resolve's API can only READ
node contents — nothing here adds or edits FX; the panel says so. No new
Swift files — pull and build.

- [ ] 1. Colour tab shows the NODE FX panel under NODE & CLIP.
- [ ] 2. On a clip with FX (e.g. a node with Color Space Transform + Film
       Look Creator, another with Film Grain): each node card lists its
       index, label, and FX names.
- [ ] 3. The stepper-selected node's card is highlighted; stepping the
       node refreshes the highlight.
- [ ] 4. Adding/deleting a node in Resolve is picked up (the panel
       refreshes when the node count changes).
- [ ] 5. Nodes without FX honestly show "no FX".
- [ ] 6. No clip at the playhead → the panel shows the reason, no crash.
- [ ] 7. Settings → Resolve capabilities → NODES group shows "Read node
       FX (GetToolsInNode): supported" after a probe.
- [ ] 8. Grading while the panel is visible stays smooth (the inventory
       answers on the reader thread, never queued behind wheel batches).
- [ ] 9. Colour wheels/knobs/presets, Fusion tab, Edit mode — unchanged.
