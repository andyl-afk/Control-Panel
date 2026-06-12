#!/usr/bin/env python3
"""Resolve colour bridge sidecar for Resolve Remote.

Reads newline-delimited JSON colour commands on stdin, applies them to node 1
of the current clip via DaVinci Resolve's scripting API (SetCDL), and writes
newline-delimited JSON color_state replies on stdout. stderr is for logs.

Requires DaVinci Resolve STUDIO with external scripting set to Local
(Preferences -> System -> General). The Swift helper sets RESOLVE_SCRIPT_API /
RESOLVE_SCRIPT_LIB / PYTHONPATH before spawning this script.

The Resolve API has no getter for CDL values, so this script keeps a shadow
copy of the four CDL parameters per clip (keyed by TimelineItem.GetUniqueId()).
If a clip was graded by other means first, our first write overwrites node 1's
CDL with the shadow state — a known v1 limitation.
"""

import json
import queue
import sys
import threading
import time

# ---------------------------------------------------------------------------
# Tunables
# ---------------------------------------------------------------------------

# Per-tick step sizes (multiplied by the speed value sent from the phone).
STEP_SLOPE = 0.005    # gain
STEP_OFFSET = 0.002   # lift
STEP_POWER = 0.005    # gamma
STEP_SAT = 0.01       # saturation, per slider step

# Clamps (min, max) for each CDL parameter.
CLAMP_SLOPE = (0.0, 4.0)
CLAMP_OFFSET = (-1.0, 1.0)
CLAMP_POWER = (0.05, 4.0)
CLAMP_SAT = (0.0, 4.0)

# Wheel-right on GAMMA must brighten midtones, and CDL Power gets *smaller*
# as midtones brighten — so gamma wheel ticks are inverted before applying.
GAMMA_WHEEL_INVERSION = -1.0

# SetCDL is applied at most this many times per second; deltas arriving in
# between are summed and applied together.
MAX_APPLIES_PER_SECOND = 30.0

# We only ever touch node 1.
NODE_INDEX = "1"

DEFAULT_STATE = {"slope": 1.0, "offset": 0.0, "power": 1.0, "sat": 1.0}

# Maps the phone's target names to shadow-state keys, step sizes, clamps and
# the direction multiplier for wheel ticks.
TARGETS = {
    "gain": ("slope", STEP_SLOPE, CLAMP_SLOPE, 1.0),
    "lift": ("offset", STEP_OFFSET, CLAMP_OFFSET, 1.0),
    "gamma": ("power", STEP_POWER, CLAMP_POWER, GAMMA_WHEEL_INVERSION),
}


def emit(obj):
    """One JSON reply line on stdout (the helper forwards it to the phone)."""
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


def log(message):
    sys.stderr.write(message + "\n")
    sys.stderr.flush()


# ---------------------------------------------------------------------------
# Resolve connection
# ---------------------------------------------------------------------------

class ResolveSession:
    """Lazily connects to Resolve and survives Resolve quitting/restarting."""

    def __init__(self):
        self.resolve = None
        self.reason = "Not connected to Resolve yet"

    def connect(self):
        try:
            import DaVinciResolveScript as dvr  # noqa: N813
        except Exception as exc:
            self.resolve = None
            self.reason = (
                "Could not load the DaVinci Resolve scripting module (%s). "
                "Is Resolve installed, and is the helper's PYTHONPATH correct?" % exc
            )
            return False
        try:
            self.resolve = dvr.scriptapp("Resolve")
        except Exception as exc:
            self.resolve = None
            self.reason = "Could not connect to Resolve: %s" % exc
            return False
        if self.resolve is None:
            self.reason = (
                "Resolve is not running, or external scripting is unavailable. "
                "Resolve STUDIO is required, with Preferences > System > General > "
                "'External scripting using' set to Local."
            )
            return False
        self.reason = None
        return True

    def current_item(self):
        """Returns (timeline_item, error_reason). Exactly one is not None."""
        if self.resolve is None and not self.connect():
            return None, self.reason
        try:
            manager = self.resolve.GetProjectManager()
            project = manager.GetCurrentProject() if manager else None
            if project is None:
                return None, "No project is open in Resolve"
            timeline = project.GetCurrentTimeline()
            if timeline is None:
                return None, "No timeline is open in Resolve"
            item = timeline.GetCurrentVideoItem()
            if item is None:
                return None, "No video clip at the playhead"
            return item, None
        except Exception as exc:
            # Resolve most likely quit; drop the handle so the next command
            # attempts a fresh connection.
            self.resolve = None
            return None, "Lost connection to Resolve (%s)" % exc


# ---------------------------------------------------------------------------
# Shadow state + command application
# ---------------------------------------------------------------------------

class ColorEngine:
    def __init__(self):
        self.session = ResolveSession()
        self.states = {}          # clip unique id -> dict like DEFAULT_STATE
        self.current_uid = None
        self.last_available = None  # tri-state: None / True / False

    def state_for(self, item):
        uid = item.GetUniqueId()
        if uid != self.current_uid:
            self.current_uid = uid
            self.states.setdefault(uid, dict(DEFAULT_STATE))
        return self.states[self.current_uid]

    def process_batch(self, batch):
        """Apply a drained batch of commands with one SetCDL at the end."""
        wants_status = any(c.get("cmd") == "color_status" for c in batch)
        mutating = [c for c in batch if c.get("cmd") != "color_status"]

        item, reason = self.session.current_item()
        if item is None:
            if mutating:
                log("dropping %d colour command(s): %s" % (len(mutating), reason))
            self.announce(False, reason=reason, force=wants_status)
            return

        state = self.state_for(item)
        changed = False

        for cmd in mutating:
            name = cmd.get("cmd")
            if name == "color_delta":
                target = TARGETS.get(cmd.get("target"))
                if target is None:
                    log("unknown color_delta target: %r" % cmd.get("target"))
                    continue
                key, step, clamp, direction = target
                ticks = cmd.get("ticks") or 0
                speed = cmd.get("speed") or 1.0
                state[key] = clamped(state[key] + ticks * step * speed * direction, clamp)
                changed = True
            elif name == "sat_delta":
                steps = cmd.get("steps") or 0
                speed = cmd.get("speed") or 1.0
                state["sat"] = clamped(state["sat"] + steps * STEP_SAT * speed, CLAMP_SAT)
                changed = True
            elif name == "color_reset":
                target = cmd.get("target")
                if target == "all":
                    state.update(DEFAULT_STATE)
                    changed = True
                elif target == "sat":
                    state["sat"] = DEFAULT_STATE["sat"]
                    changed = True
                elif target in TARGETS:
                    key = TARGETS[target][0]
                    state[key] = DEFAULT_STATE[key]
                    changed = True
                else:
                    log("unknown color_reset target: %r" % target)
            else:
                log("unknown colour command: %r" % name)

        if changed:
            ok = self.apply_cdl(item, state)
            if not ok:
                self.announce(False, reason="Resolve rejected SetCDL on node 1", force=True)
                return

        if changed or wants_status:
            self.announce(True, item=item, state=state, force=True)
        else:
            self.announce(True, item=item, state=state, force=False)

    def apply_cdl(self, item, state):
        def triplet(value):
            return "%.6f %.6f %.6f" % (value, value, value)

        try:
            return bool(item.SetCDL({
                "NodeIndex": NODE_INDEX,
                "Slope": triplet(state["slope"]),
                "Offset": triplet(state["offset"]),
                "Power": triplet(state["power"]),
                "Saturation": "%.6f" % state["sat"],
            }))
        except Exception as exc:
            log("SetCDL failed: %s" % exc)
            self.session.resolve = None
            return False

    def announce(self, available, item=None, state=None, reason=None, force=False):
        """Emit color_state when availability flips, or when forced."""
        if not force and available == self.last_available:
            return
        self.last_available = available
        if available:
            clip_name = "?"
            try:
                clip_name = item.GetName()
            except Exception:
                pass
            emit({
                "v": 1,
                "cmd": "color_state",
                "available": True,
                "clip": clip_name,
                "lift": round(state["offset"], 6),
                "gamma": round(state["power"], 6),
                "gain": round(state["slope"], 6),
                "sat": round(state["sat"], 6),
            })
        else:
            emit({"v": 1, "cmd": "color_state", "available": False, "reason": reason})


def clamped(value, bounds):
    low, high = bounds
    return max(low, min(high, value))


# ---------------------------------------------------------------------------
# Main loop: stdin reader thread + rate-limited batch worker
# ---------------------------------------------------------------------------

def main():
    commands = queue.Queue()
    sentinel = object()

    def read_stdin():
        for line in sys.stdin:
            line = line.strip()
            if not line:
                continue
            try:
                commands.put(json.loads(line))
            except ValueError:
                log("ignoring malformed JSON: %s" % line)
        commands.put(sentinel)  # stdin closed: the helper went away

    threading.Thread(target=read_stdin, daemon=True).start()

    log("resolve_bridge started (python %s)" % sys.version.split()[0])
    engine = ColorEngine()
    # Report initial availability without blocking startup on Resolve.
    if engine.session.connect():
        log("connected to Resolve")
    else:
        log("Resolve not reachable yet: %s" % engine.session.reason)

    min_interval = 1.0 / MAX_APPLIES_PER_SECOND
    last_apply = 0.0

    while True:
        cmd = commands.get()  # block until there is work
        if cmd is sentinel:
            break

        batch = [cmd]
        # Respect the SetCDL rate limit, then drain everything that arrived
        # in the meantime so it is applied as a single batch. Because the
        # batch is processed immediately after the wait, the final ticks of
        # a gesture are never held back.
        wait = min_interval - (time.time() - last_apply)
        if wait > 0:
            time.sleep(wait)
        while True:
            try:
                batch.append(commands.get_nowait())
            except queue.Empty:
                break

        # Process whatever arrived before the shutdown sentinel, then exit.
        shutting_down = any(item is sentinel for item in batch)
        batch = [item for item in batch if item is not sentinel]
        if batch:
            engine.process_batch(batch)
            last_apply = time.time()
        if shutting_down:
            break

    log("stdin closed, exiting")


if __name__ == "__main__":
    main()
