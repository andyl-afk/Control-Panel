# Phase 8 Testing Checklist — Node Targeting

Prerequisites: Phase 7 working. Use a clip with 3 nodes in Resolve (add
serial nodes on the Color page first).

- [ ] **Stepper reflects the tree.**
  On a 3-node clip the stepper shows NODE 1/3 … 3/3; the left chevron
  disables at 1, the right at 3.

- [ ] **Grades land on the selected node.**
  Step to node 2, grade with wheel/trackball/knobs: only node 2's
  thumbnail changes in Resolve's node graph; nodes 1 and 3 stay clean.
  (Resolve's highlighted node will NOT follow the stepper — API
  limitation, expected.)

- [ ] **Per-node values are independent.**
  Set distinct grades on nodes 1 and 2, step back and forth: readouts,
  knob values, and puck positions snap to each node's own state.

- [ ] **Bypass targets the active node.**
  On node 2, hold BEFORE/AFTER: only node 2 disables. Kill the app
  mid-hold: node 2 is re-enabled automatically.

- [ ] **Clamping on clip change.**
  While on node 3, move the playhead to a 1-node clip and touch a wheel:
  the stepper clamps to NODE 1/1 (dimmed, chevrons hidden) and grading
  works on node 1.

- [ ] **Preset purges all nodes.**
  Trim nodes 1 and 2, apply a look: stepping through every node shows
  default readouts (the DRX may have rewritten the whole tree).

- [ ] **Single-node clip UI.**
  On a 1-node clip the stepper shows "NODE 1/1" dimmed with no chevrons.

- [ ] **Persistence.**
  Grade two nodes, close and reopen the project: both nodes' grades are
  still on the clip.

## Phase 8.1 — node freshness

- [ ] **Added nodes appear without phone interaction.**
  With the Colour tab open and connected, add a node in Resolve: within
  ~2 s the stepper updates (e.g. 1/1 → 1/2) with no taps, no haptics,
  and no visual flashing.

- [ ] **Fresh targeting.**
  Step to node 2, adjust gain: Resolve's node 2 thumbnail changes,
  node 1 untouched.

- [ ] **Deleted node clamps safely.**
  Delete node 2 in Resolve while the app targets it: within ~2 s the
  stepper clamps to 1/1, and the next adjustment lands on node 1 with no
  errors in the helper log.

- [ ] **Full regression.**
  Phase 1–7 checklists pass.
