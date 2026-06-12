# Phase 9 Testing Checklist — Menu Bar Helper + Bonjour

Prerequisites: the Resolve Remote Helper target built per DEVELOPMENT.md;
iOS target has NSBonjourServices = ["_resolveremote._tcp"].

- [ ] **Zero-terminal launch.**
  Launch the helper app from Finder: the dial icon appears in the menu
  bar, the menu shows "Running on port 49321 — 0 clients", no Terminal
  involved, no Dock icon, no window.

- [ ] **Launch at Login survives reboot.**
  Toggle it on, reboot the Mac: the helper is back in the menu bar and
  the toggle still shows on.

- [ ] **Accessibility flow.**
  Revoke the permission in System Settings, relaunch the helper: the
  explainer alert appears once (and only once — relaunch again to
  confirm no nag). Its button and the menu's "Grant Accessibility
  Access…" both land on Privacy & Security → Accessibility. Granting
  makes Edit-mode keys work.

- [ ] **Client count live.**
  Connect and disconnect the phone: the menu line counts 0 → 1 → 0 and
  the menu bar icon switches to its filled variant while connected.

- [ ] **Quit kills the sidecar.**
  With the helper running, find python3 (resolve_bridge) in Activity
  Monitor. Quit from the menu: the python3 process disappears — no
  orphan. (Force-quitting the helper also ends it, via stdin EOF.)

- [ ] **Discovery and tap-to-connect.**
  On the phone, Settings → NEARBY MACS lists the Mac by name within a
  few seconds. Tapping Connect goes green without any IP entry.

- [ ] **Auto-connect via Bonjour.**
  Kill and relaunch the iPhone app: it reconnects to the same Mac by
  service name. Switch the phone to another network and back: it
  reconnects once both are on the same network again.

- [ ] **Manual IP fallback.**
  Quit the helper app and run the CLI with Bonjour somehow unavailable
  (or just test on a network that blocks mDNS): entering the IP under
  CONNECTION still connects, and stays the preference until a Nearby
  Mac is tapped again.

- [ ] **Dry-run toggle.**
  Enable Dry-run in the menu: phone buttons log on the helper but no
  keys reach Resolve; disable: keys work again. Setting persists across
  helper relaunches.

- [ ] **Full regression.**
  Phase 1–8.1 checklists pass: Edit (jog/shuttle/scrub, transport,
  shortcuts), Colour (wheels, trackball, knobs, compare, stills),
  nodes (stepper, freshness), Looks, persistence.
