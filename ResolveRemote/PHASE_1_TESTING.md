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

- [ ] **Keyboard dismisses.**
  Tap the IP or port field so the keyboard appears. Tapping "Done" in the
  keyboard toolbar dismisses it; tapping Connect also dismisses it.

- [ ] **Scrub mode moves ~10 frames per detent.**
  Select SCRUB and rotate the wheel: each detent sends `cmd=jog` with
  ticks multiplied by 10 (e.g. `ticks=10` / `ticks=-10`), so in send-keys
  mode the playhead moves about 10 frames per detent.

- [ ] **Shuttle mode holds playback speed and stops on release.**
  Select SHUTTLE and rotate-and-hold: the helper logs `cmd=shuttle` with
  `level=` -3..+3, only when the level changes, with a heavy haptic bump
  per change. In send-keys mode each level presses K then J/L repeats
  (Resolve J/K/L shuttle), so playback holds that speed. Releasing the
  wheel snaps it back to centre and sends `level=0` (K = stop).

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
  between edit points, Undo undoes, Blade fires Cmd+K (add edit on the
  Premiere-style keymap), Ripple fires Shift+ForwardDelete (ripple delete).

- [ ] **Haptics fire locally on iPhone.**
  Wheel rotation gives a light tick per detent, reversing direction gives a
  sharper tick, every button gives a tap. (Real device only — the Simulator
  has no Taptic Engine.)
