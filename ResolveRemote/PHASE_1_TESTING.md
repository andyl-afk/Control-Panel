# Phase 1 Testing Checklist

Work through these in order. Everything before the send-keys section can be
done with the helper in dry-run mode.

- [ ] **Helper starts in dry-run mode.**
  `cd ResolveRemote/macOS-helper && swift run ResolveHelper`
  Banner shows `Mode: DRY-RUN`, the port, and at least one local IP.

- [ ] **iPhone connects by IP.**
  Enter the Mac IP and port 49321 in the app, tap Connect. Status turns
  green "Connected"; helper logs `client #1 connected`.

- [ ] **Ping logs on helper.**
  From a second terminal on the Mac:
  `echo '{"v":1,"seq":1,"mode":"edit","cmd":"ping","ts":0}' | nc localhost 49321`
  Helper logs the ping. (The app itself doesn't expose a ping button.)

- [ ] **Button taps log on helper.**
  Tap each transport and shortcut button. Helper logs one decoded command
  per tap with an incrementing `seq` (play_pause, step_left/right,
  shuttle_left/right, blade, ripple_delete, marker, undo, in_point,
  out_point, prev_edit, next_edit).

- [ ] **Jog wheel sends jog ticks.**
  Rotate clockwise → `cmd=jog` with positive ticks. Counter-clockwise →
  negative ticks. Higher Speed slider → more ticks for the same rotation.

- [ ] **Bad JSON does not crash helper.**
  `printf 'this is not json\n{"broken\n' | nc localhost 49321`
  Helper logs "ignoring malformed JSON" twice and keeps serving.

- [ ] **Helper can be restarted and app reconnects.**
  Ctrl-C the helper → app shows an error state. Start the helper again,
  tap Connect → green again, commands flow.

- [ ] **send-keys mode sends Space/Arrow keys into TextEdit first.**
  `swift run ResolveHelper --send-keys` (banner shows Accessibility is
  granted). Open TextEdit, make it frontmost. From the phone: Marker types
  `m`, In/Out type `i`/`o`, play/pause types a space, step buttons move the
  cursor, the jog wheel moves the cursor repeatedly, Undo (Cmd-Z) undoes
  typing.

- [ ] **send-keys mode drives DaVinci Resolve when Resolve is frontmost.**
  Open a timeline in Resolve, click into it. From the phone: play/pause
  toggles playback, step buttons and jog move the playhead, M drops a
  marker, I/O set in/out points, Prev/Next Edit (Up/Down arrow) jump
  between edit points, Undo undoes.

- [ ] **Haptics fire locally on iPhone.**
  Wheel rotation gives a light tick per detent, reversing direction gives a
  sharper tick, every button gives a tap. (Real device only — the Simulator
  has no Taptic Engine.)
