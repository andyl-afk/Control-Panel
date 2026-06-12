# Resolve Remote — Phase 1

An iPhone haptic controller for DaVinci Resolve.

Phase 1 is the minimum working bridge:

```
iPhone app  --TCP, newline-delimited JSON-->  macOS helper  -->  log command
                                                            -->  (optionally) keyboard events via CGEvent
```

## What Phase 1 does

- A SwiftUI iPhone app with an Edit Mode screen: jog wheel, speed slider,
  JOG/SHUTTLE/SCRUB selector (all behave as jog for now), transport buttons,
  and shortcut buttons (Blade, Ripple, Marker, Undo, In, Out, Prev/Next Edit).
- Local haptics on the iPhone (wheel ticks, direction changes, button taps).
- A macOS command-line helper (`ResolveHelper`) that listens on TCP port
  **49321**, decodes JSON commands, and logs them.
- An optional `--send-keys` mode where the helper sends real keyboard events
  (Space, arrows, I, O, M, Cmd-Z, …) directly to DaVinci Resolve when it's
  running (it doesn't need to be frontmost), or to the frontmost app when
  Resolve isn't running (handy for TextEdit testing).
- Manual IP entry. Works over normal Wi-Fi, or over USB-C networking /
  Personal Hotspot, because the app just connects to a host IP and port.

## What Phase 1 intentionally does NOT do

- No Colour Mode.
- No DaVinci Resolve scripting API integration.
- No Bonjour/auto-discovery — you type the Mac's IP manually.
- No accounts, cloud, or sync.
- No iPad layouts.
- No raw USB APIs.
- The `<<`/`>>` transport buttons (shuttle_left/shuttle_right) are **log-only**
  on the helper; the wheel's SHUTTLE mode uses J/K/L instead.

## Repo layout

```
ResolveRemote/
  iOS/ResolveRemote/    Swift sources for the iPhone app (add to an Xcode project — see below)
  macOS-helper/         Swift Package for the ResolveHelper command-line tool
  README.md
  PHASE_1_TESTING.md
```

## 1. Run the macOS helper

Requires macOS 13+ with Xcode (or the Command Line Tools) installed.

```sh
cd ResolveRemote/macOS-helper

# Dry-run mode (default) — logs every command, sends no keys. Start here.
swift run ResolveHelper

# Send-keys mode — actually sends keyboard events to the frontmost app.
swift run ResolveHelper --send-keys

# Custom port if 49321 is taken:
swift run ResolveHelper --port 50000
```

On startup the helper prints its mode, port, and the Mac's local IP
addresses — type one of those into the iPhone app.

### Quick smoke test without the phone

With the helper running, from another terminal on the Mac:

```sh
echo '{"v":1,"seq":1,"mode":"edit","cmd":"ping","ts":0}' | nc localhost 49321
```

You should see the ping logged by the helper.

### Accessibility permission (required for `--send-keys`)

macOS only allows a process to synthesize keyboard events if it has the
**Accessibility** permission:

1. Open **System Settings → Privacy & Security → Accessibility**.
2. Enable the app that runs the helper — usually **Terminal** or **iTerm2**
   (if you run it from Xcode, enable Xcode).
3. Restart the helper.

The helper checks `AXIsProcessTrusted()` at startup and prints a warning if
the permission is missing. Without it, the helper keeps running but macOS
silently drops the key events.

## 2. Build the iPhone app

There is no checked-in `.xcodeproj` — create one and add the sources:

1. In Xcode: **File → New → Project… → iOS → App**.
   - Product Name: **ResolveRemote**
   - Interface: **SwiftUI**, Language: **Swift**
2. Delete the template `ContentView.swift` and the template
   `ResolveRemoteApp.swift` that Xcode generated.
3. Drag the folders inside `ResolveRemote/iOS/ResolveRemote/`
   (`App`, `Models`, `Networking`, `Haptics`, `Views`, `Components`) into the
   project navigator. Check **"Copy items if needed"** is *off* if you want to
   keep editing the files in the repo, and make sure they're added to the
   ResolveRemote target.
4. Add the local-network usage description. In the target's **Info** tab add:
   - Key: `NSLocalNetworkUsageDescription`
     (shown as *Privacy - Local Network Usage Description*)
   - Value: `Resolve Remote connects to the Mac helper on your local network to control DaVinci Resolve.`

   No Bonjour service keys are needed — Phase 1 uses manual IP entry.
5. Select your iPhone as the run destination and run. (The Simulator also
   works for testing against `localhost` networking on the same Mac, but
   haptics only work on a real device.)

## 3. Find your Mac's IP address

The helper prints it at startup. Otherwise:

- **Wi-Fi:** `ipconfig getifaddr en0` in Terminal, or
  System Settings → Wi-Fi → Details… → IP address.
- **USB-C / Hotspot:** see section 5 below.

## 4. Connect from the iPhone (Wi-Fi)

1. Make sure the iPhone and Mac are on the **same Wi-Fi network**.
2. Start the helper on the Mac (`swift run ResolveHelper`).
3. In the app, enter the Mac's IP, leave the port at **49321**, tap
   **Connect**. iOS will ask for local-network permission the first time —
   allow it.
4. The status dot turns green; the helper logs `client #1 connected`.
5. Tap buttons / spin the wheel and watch the commands appear in the helper's
   log.

## 5. Connect over USB-C networking / Personal Hotspot

The app just connects to an IP, so any network path works:

- **Personal Hotspot:** enable the hotspot on the iPhone and join it from the
  Mac (Wi-Fi menu). Restart the helper and use the IP it prints for that
  connection (often `172.20.10.x`).
- **USB tethering:** plug the iPhone into the Mac with USB-C, enable Personal
  Hotspot; the Mac shows an "iPhone USB" network interface. Restart the helper
  and use the IP it prints for that interface. This gives the lowest latency.

## 6. Testing key sending

1. Run `swift run ResolveHelper --send-keys` (Accessibility granted).
2. **Start with TextEdit**, not Resolve (quit Resolve first — when it's
   running the helper targets it directly): open TextEdit, make it frontmost,
   then press Marker/In/Out on the phone — `m`, `i`, `o` should appear; the
   step buttons move the cursor; play/pause types spaces.
3. Then switch to DaVinci Resolve, make it frontmost, and the same buttons
   drive the timeline: Space = play/pause, arrows = step, M = marker,
   I/O = in/out, Cmd-Z = undo, jog wheel = repeated arrow steps.

## Colour Mode setup (Phase 2)

Colour Mode adjusts Lift / Gamma / Gain (master value, node 1), Saturation,
and the derived Temp / Tint / Contrast / Pivot knobs on the current clip
through Resolve's scripting API, via a Python sidecar the helper spawns
automatically. The derived knobs are composed into per-channel CDL values
(they are CDL math, not Resolve's native primary controls). A hold-to-compare
button temporarily bypasses node 1.

Requirements:

1. **DaVinci Resolve Studio.** The free version does not expose the external
   scripting API — Colour Mode will show "unavailable".
2. In Resolve: **Preferences → System → General → "External scripting using"**
   must be set to **Local**. Restart Resolve after changing it.
3. **python3** must be available on the Mac (`xcode-select --install`, or
   install from python.org). The helper runs `/usr/bin/env python3`.

No extra setup beyond that — start the helper as usual and the sidecar logs
appear with a `[sidecar]` prefix.

### Known limitation: shadow state

Resolve's API can *set* CDL grades but cannot *read* them back, so the helper
keeps its own copy of the four values (lift/gamma/gain/sat) per clip. If a
clip's node 1 was already graded with the mouse, the **first wheel movement
overwrites that grade** with the helper's values (defaults, for a clip it
hasn't touched). This is a known v1 limitation — use Resolve's undo if it
bites you.

### Looks (Phase 4)

Look presets are plain `.drx` files in **`~/ResolveRemote/Looks/`** on the
Mac (the sidecar creates the folder on startup). The folder *is* the
management UI — there is nothing to configure on the phone.

**Saving a look from Resolve:**

1. On the Color page, grade a clip, then grab a still into the Gallery
   (right-click the viewer → Grab Still).
2. In the Gallery, right-click the still → **Export**, and save it into
   `~/ResolveRemote/Looks/` with a meaningful filename — Resolve writes a
   `.drx` alongside the image. Only the `.drx` matters here.
3. The filename (without extension) is the button name on the phone. Tap
   the refresh icon in the LOOKS row to pick up new files.

**What applying a look does:** `ApplyGradeFromDRX` replaces the clip's whole
node grade with the preset, and the app's wheel/knob trim layer resets to
neutral — the look becomes the new base, and any wheel or knob movement
afterwards trims on top of it.

**Why looks matter:** a `.drx` can contain *anything* Resolve can grade —
curves, power windows, mid-detail, noise reduction, multiple nodes and
corrections. This is how you reach controls the scripting API doesn't
expose: build the look in Resolve once, fire it from the phone.

### Colour "unavailable" reasons

| Reason shown on the phone | Meaning |
| --- | --- |
| Could not load the DaVinci Resolve scripting module… | The scripting API files weren't found — is Resolve installed in the standard location? |
| Resolve is not running, or external scripting is unavailable… | Start Resolve Studio; check the External scripting preference is Local; the free version always shows this. |
| No project / timeline is open | Open a project and a timeline in Resolve. |
| No video clip at the playhead | Move the playhead over a clip. |
| Lost connection to Resolve… | Resolve quit or crashed — reopen it and tap Retry. |
| Colour sidecar stopped / Could not start python3… | Check python3 is installed; look for `[sidecar]` errors in the helper console. |

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| App says "Connection refused" | Helper isn't running, or wrong port. |
| App says "Timed out" / "Host unreachable" | Wrong IP, or phone and Mac are on different networks. Re-check the IP the helper printed. |
| Connects but nothing in Resolve | You're in dry-run mode — restart with `--send-keys`. |
| `--send-keys` but no keys arrive anywhere | Accessibility permission missing — grant it and restart the helper. |
| Keys go to the wrong app | When Resolve is running, keys are sent straight to it. When it isn't, keys go to the *frontmost* app — quit Resolve fully if you're trying to test in TextEdit. |
| "listener failed" at startup | Port already in use — another helper is running, or pass `--port`. |
| First connect prompt never appeared / connection blocked | iOS Settings → Privacy & Security → Local Network → enable ResolveRemote. Also check the Mac's firewall (System Settings → Network → Firewall) isn't blocking incoming connections. |
| Helper was restarted | The app shows an error state; tap Connect again. |

See `PHASE_1_TESTING.md` for the full acceptance checklist.
