#!/usr/bin/env python3
"""Resolve colour bridge sidecar for Resolve Remote.

Reads newline-delimited JSON colour commands on stdin, applies them to node 1
of the current clip via DaVinci Resolve's scripting API (SetCDL), and writes
newline-delimited JSON color_state replies on stdout. stderr is for logs.

Requires DaVinci Resolve STUDIO with external scripting set to Local
(Preferences -> System -> General). The Swift helper sets RESOLVE_SCRIPT_API /
RESOLVE_SCRIPT_LIB / PYTHONPATH before spawning this script.

Phase 3: the per-clip shadow state holds eight USER parameters (masters, sat,
temp, tint, contrast, pivot); compose_cdl() composes them into per-channel
CDL values on every apply. Bypass (hold-to-compare) toggles node 1 on/off,
bypassing the rate limiter.

The Resolve API has no getter for CDL values, so this script keeps a shadow
copy of the parameters per clip (keyed by TimelineItem.GetUniqueId()). If a
clip was graded by other means first, our first write overwrites node 1's
CDL with the shadow state — a known limitation.
"""

import json
import math
import os
import queue
import sys
import threading
import time

# ---------------------------------------------------------------------------
# Tunables
# ---------------------------------------------------------------------------

# Per-step sizes (multiplied by the speed value sent from the phone).
STEP_GAIN = 0.005      # color_delta gain (wheel)
STEP_LIFT = 0.002      # color_delta lift (wheel)
STEP_GAMMA = 0.005     # color_delta gamma (wheel)
STEP_SAT = 0.01        # param_delta sat
STEP_TEMP = 0.01       # param_delta temp
STEP_TINT = 0.01       # param_delta tint
STEP_CONTRAST = 0.01   # param_delta contrast
STEP_PIVOT = 0.005     # param_delta pivot

# How strongly temp/tint skew the slope channels.
TEMP_STRENGTH = 0.3
TINT_STRENGTH = 0.3

# How strongly a full-magnitude trackball balance deflects each parameter.
BAL_LIFT_STRENGTH = 0.15    # additive on offset
BAL_GAIN_STRENGTH = 0.25    # multiplicative on slope
BAL_GAMMA_STRENGTH = 0.25   # multiplicative on power (inverted, like master)

# Wheel-right on GAMMA must brighten midtones, and CDL Power gets *smaller*
# as midtones brighten — so gamma wheel ticks are inverted before applying.
# The stored gamma_m is the actual CDL power value.
GAMMA_WHEEL_INVERSION = -1.0

# User-parameter clamps (min, max).
CLAMP_GAIN_M = (0.0, 4.0)
CLAMP_LIFT_M = (-1.0, 1.0)
CLAMP_GAMMA_M = (0.05, 4.0)
CLAMP_SAT = (0.0, 4.0)
CLAMP_TEMP = (-1.0, 1.0)
CLAMP_TINT = (-1.0, 1.0)
CLAMP_CONTRAST = (0.0, 2.0)
CLAMP_PIVOT = (0.0, 1.0)

# Final per-channel clamps applied after composition.
CLAMP_CH_SLOPE = (0.0, 4.0)
CLAMP_CH_POWER = (0.05, 4.0)
CLAMP_CH_OFFSET = (-1.0, 1.0)

# SetCDL is applied at most this many times per second; deltas arriving in
# between are summed and applied together. Bypass skips this limiter.
MAX_APPLIES_PER_SECOND = 30.0

# We only ever touch node 1.
NODE_INDEX = "1"
NODE_NUMBER = 1  # integer form for SetNodeEnabled

# Look presets: every .drx file in this folder is a preset; the filename
# (without extension) is the button name on the phone. The folder is the
# management UI — the sidecar re-scans it on every list request.
LOOKS_DIR = os.path.expanduser("~/ResolveRemote/Looks")

# 0.435 is Resolve's default contrast pivot.
USER_DEFAULTS = {
    "lift_m": 0.0,
    "gamma_m": 1.0,
    "gain_m": 1.0,
    "sat": 1.0,
    "temp": 0.0,
    "tint": 0.0,
    "contrast": 1.0,
    "pivot": 0.435,
}

# color_delta target -> (state key, step, clamp, wheel direction)
WHEEL_TARGETS = {
    "gain": ("gain_m", STEP_GAIN, CLAMP_GAIN_M, 1.0),
    "lift": ("lift_m", STEP_LIFT, CLAMP_LIFT_M, 1.0),
    "gamma": ("gamma_m", STEP_GAMMA, CLAMP_GAMMA_M, GAMMA_WHEEL_INVERSION),
}

# param_delta param -> (state key, step, clamp)
KNOB_PARAMS = {
    "sat": ("sat", STEP_SAT, CLAMP_SAT),
    "temp": ("temp", STEP_TEMP, CLAMP_TEMP),
    "tint": ("tint", STEP_TINT, CLAMP_TINT),
    "contrast": ("contrast", STEP_CONTRAST, CLAMP_CONTRAST),
    "pivot": ("pivot", STEP_PIVOT, CLAMP_PIVOT),
}

# color_delta target -> balance vector key (trackball, Phase 7).
BALANCE_KEYS = {
    "lift": "bal_lift",
    "gamma": "bal_gamma",
    "gain": "bal_gain",
}


def fresh_state():
    """A new clip's shadow state. Balance vectors are created per call so
    list instances are never shared between clips."""
    state = dict(USER_DEFAULTS)
    for key in BALANCE_KEYS.values():
        state[key] = [0.0, 0.0]
    return state


# color_reset target -> state key ("all" handled separately)
RESET_TARGETS = {
    "lift": "lift_m",
    "gamma": "gamma_m",
    "gain": "gain_m",
    "sat": "sat",
    "temp": "temp",
    "tint": "tint",
    "contrast": "contrast",
    "pivot": "pivot",
}


def clamped(value, bounds):
    low, high = bounds
    return max(low, min(high, value))


def clamp_balance(vec):
    """Clamp a balance vector's magnitude to 1.0, preserving direction."""
    magnitude = math.hypot(vec[0], vec[1])
    if magnitude > 1.0:
        vec[0] /= magnitude
        vec[1] /= magnitude
    return vec


def _balance_weights(vec):
    """Per-channel weights for a trackball balance vector.

    RED sits at the top of the wheel and the hue axes are 120 degrees
    apart. The three weights always sum to zero, so a balance shifts hue
    without shifting overall level — that invariant is what makes the
    trackball feel like a panel trackball and not a gain knob.
    """
    x, y = vec[0], vec[1]
    magnitude = math.hypot(x, y)
    if magnitude == 0.0:
        return 0.0, (0.0, 0.0, 0.0)
    theta = math.atan2(y, x)
    w_r = math.cos(theta - math.radians(90))
    w_g = math.cos(theta - math.radians(210))
    w_b = math.cos(theta - math.radians(330))
    return magnitude, (w_r, w_g, w_b)


def compose_cdl(params):
    """Pure function: user parameters -> SetCDL payload dict.

    Composition order (per spec):
      1. base RGB triplets from the masters
      1.5 trackball balance per parameter (zero-sum hue weights)
      2. temperature skews slope R/B
      3. tint skews slope G (and counters on R/B)
      4. contrast scales slope and re-anchors offset around the pivot
      5. per-channel clamps
    """
    slope = [params["gain_m"]] * 3
    offset = [params["lift_m"]] * 3
    # gamma_m already holds the (wheel-inverted) CDL power value.
    power = [params["gamma_m"]] * 3

    # Step 1.5 — trackball balance. Lift is additive on offset; gain is
    # multiplicative on slope; gamma is multiplicative on power with the
    # same inversion convention as the master gamma wheel.
    m, w = _balance_weights(params.get("bal_lift", (0.0, 0.0)))
    offset = [offset[i] + m * w[i] * BAL_LIFT_STRENGTH for i in range(3)]
    m, w = _balance_weights(params.get("bal_gain", (0.0, 0.0)))
    slope = [slope[i] * (1 + m * w[i] * BAL_GAIN_STRENGTH) for i in range(3)]
    m, w = _balance_weights(params.get("bal_gamma", (0.0, 0.0)))
    power = [power[i] * (1 - m * w[i] * BAL_GAMMA_STRENGTH) for i in range(3)]

    temp = params["temp"]
    slope[0] *= (1 + temp * TEMP_STRENGTH)
    slope[2] *= (1 - temp * TEMP_STRENGTH)

    tint = params["tint"]
    slope[1] *= (1 + tint * TINT_STRENGTH)
    slope[0] *= (1 - tint * TINT_STRENGTH * 0.5)
    slope[2] *= (1 - tint * TINT_STRENGTH * 0.5)

    contrast = params["contrast"]
    pivot = params["pivot"]
    slope = [s * contrast for s in slope]
    offset = [o * contrast + pivot * (1 - contrast) for o in offset]

    slope = [clamped(s, CLAMP_CH_SLOPE) for s in slope]
    power = [clamped(p, CLAMP_CH_POWER) for p in power]
    offset = [clamped(o, CLAMP_CH_OFFSET) for o in offset]

    def triplet(values):
        return "%.6f %.6f %.6f" % tuple(values)

    return {
        "NodeIndex": NODE_INDEX,
        "Slope": triplet(slope),
        "Offset": triplet(offset),
        "Power": triplet(power),
        "Saturation": "%.6f" % clamped(params["sat"], CLAMP_SAT),
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

    def current_context(self):
        """Returns (timeline, item, error_reason).

        `reason` is set whenever `item` is None; `timeline` may still be
        valid in that case (grab_still only needs the timeline).
        """
        if self.resolve is None and not self.connect():
            return None, None, self.reason
        try:
            manager = self.resolve.GetProjectManager()
            project = manager.GetCurrentProject() if manager else None
            if project is None:
                return None, None, "No project is open in Resolve"
            timeline = project.GetCurrentTimeline()
            if timeline is None:
                return None, None, "No timeline is open in Resolve"
            item = timeline.GetCurrentVideoItem()
            if item is None:
                return timeline, None, "No video clip at the playhead"
            return timeline, item, None
        except Exception as exc:
            # Resolve most likely quit; drop the handle so the next command
            # attempts a fresh connection.
            self.resolve = None
            return None, None, "Lost connection to Resolve (%s)" % exc


# ---------------------------------------------------------------------------
# Shadow state + command application
# ---------------------------------------------------------------------------

class ColorEngine:
    def __init__(self):
        self.session = ResolveSession()
        self.states = {}            # clip unique id -> dict like USER_DEFAULTS
        self.current_uid = None
        self.last_available = None  # tri-state: None / True / False
        self.node_bypassed = False  # last known bypass state of node 1
        # Bypass runs on the reader thread, applies on the worker — one lock
        # guards all Resolve API access.
        self.lock = threading.Lock()

    def state_for(self, item):
        uid = item.GetUniqueId()
        if uid != self.current_uid:
            self.current_uid = uid
            self.states.setdefault(uid, fresh_state())
        return self.states[self.current_uid]

    # -- bypass (hold-to-compare) -------------------------------------------

    def handle_bypass(self, enabled):
        """Called directly from the reader thread; must feel instant."""
        with self.lock:
            if enabled and not self.node_bypassed:
                return  # idempotent: nothing to re-enable
            _, item, reason = self.session.current_context()
            if item is None:
                log("bypass ignored: %s" % reason)
                return
            if self._set_node_enabled(item, enabled):
                self.node_bypassed = not enabled
                log("node %d %s" % (NODE_NUMBER, "enabled" if enabled else "bypassed"))

    def _set_node_enabled(self, item, enabled):
        try:
            # Re-fetch the graph every call — cheap, and avoids stale handles.
            graph = item.GetNodeGraph()
            if graph is None:
                log("bypass failed: clip has no node graph")
                return False
            return bool(graph.SetNodeEnabled(NODE_NUMBER, enabled))
        except Exception as exc:
            log("SetNodeEnabled failed: %s" % exc)
            return False

    # -- batched colour commands --------------------------------------------

    def process_batch(self, batch):
        """Apply a drained batch of commands with one SetCDL at the end."""
        with self.lock:
            self._process_batch_locked(batch)

    def _process_batch_locked(self, batch):
        # Preset listing is a plain folder scan — answer it even when Resolve
        # itself is unreachable.
        remaining = []
        for cmd in batch:
            if cmd.get("cmd") == "list_presets":
                self.send_preset_list()
            else:
                remaining.append(cmd)
        if not remaining:
            return

        wants_status = any(c.get("cmd") == "color_status" for c in remaining)
        mutating = [c for c in remaining if c.get("cmd") != "color_status"]

        timeline, item, reason = self.session.current_context()
        if item is None:
            if mutating:
                log("dropping %d colour command(s): %s" % (len(mutating), reason))
                # Don't leave the phone hanging on replies it expects.
                for cmd in mutating:
                    if cmd.get("cmd") == "apply_preset":
                        emit({"v": 1, "cmd": "preset_applied",
                              "name": cmd.get("name") or "?", "ok": False, "reason": reason})
                    elif cmd.get("cmd") == "grab_still":
                        emit({"v": 1, "cmd": "still_grabbed", "ok": False})
            self.announce(False, reason=reason, force=wants_status)
            return

        state = self.state_for(item)
        changed = False

        for cmd in mutating:
            name = cmd.get("cmd")
            if name == "color_delta":
                target = WHEEL_TARGETS.get(cmd.get("target"))
                if target is None:
                    log("unknown color_delta target: %r" % cmd.get("target"))
                    continue
                key, step, clamp, direction = target
                ticks = cmd.get("ticks") or 0
                speed = cmd.get("speed") or 1.0
                state[key] = clamped(state[key] + ticks * step * speed * direction, clamp)
                changed = True
            elif name == "param_delta":
                param = KNOB_PARAMS.get(cmd.get("param"))
                if param is None:
                    log("unknown param_delta param: %r" % cmd.get("param"))
                    continue
                key, step, clamp = param
                steps = cmd.get("steps") or 0
                speed = cmd.get("speed") or 1.0
                state[key] = clamped(state[key] + steps * step * speed, clamp)
                changed = True
            elif name == "balance_delta":
                bal_key = BALANCE_KEYS.get(cmd.get("target"))
                if bal_key is None:
                    log("unknown balance_delta target: %r" % cmd.get("target"))
                    continue
                # The phone pre-multiplies sensitivity and speed into dx/dy,
                # so they are applied here as-is.
                vec = state[bal_key]
                vec[0] += cmd.get("dx") or 0.0
                vec[1] += cmd.get("dy") or 0.0
                clamp_balance(vec)
                changed = True
            elif name == "color_reset":
                target = cmd.get("target")
                if target == "all":
                    state.update(fresh_state())
                    changed = True
                elif target in RESET_TARGETS:
                    key = RESET_TARGETS[target]
                    state[key] = USER_DEFAULTS[key]
                    # Master targets also clear their balance vector.
                    bal_key = BALANCE_KEYS.get(target)
                    if bal_key:
                        state[bal_key] = [0.0, 0.0]
                    changed = True
                else:
                    log("unknown color_reset target: %r" % target)
            elif name == "apply_preset":
                if self.apply_preset(item, cmd.get("name") or ""):
                    # The DRX is now the base look and the shadow state was
                    # reset — any deltas earlier in this batch are obsolete.
                    state = self.state_for(item)
                    changed = False
            elif name == "grab_still":
                self.grab_still(timeline)
            else:
                log("unknown colour command: %r" % name)

        if changed:
            # Grading while bypassed would be invisible and confusing — make
            # sure node 1 is back on before the next apply.
            if self.node_bypassed and self._set_node_enabled(item, True):
                self.node_bypassed = False
                log("node %d re-enabled before apply" % NODE_NUMBER)
            if not self.apply_cdl(item, state):
                self.announce(False, reason="Resolve rejected SetCDL on node 1", force=True)
                return

        self.announce(True, item=item, state=state, force=changed or wants_status)

    # -- look presets ---------------------------------------------------------

    def send_preset_list(self):
        """Fresh folder scan on every request — the folder is the source of
        truth, no caching, no file watching."""
        try:
            names = sorted(
                os.path.splitext(entry)[0]
                for entry in os.listdir(LOOKS_DIR)
                if entry.lower().endswith(".drx") and not entry.startswith(".")
            )
        except OSError as exc:
            log("could not scan %s: %s" % (LOOKS_DIR, exc))
            names = []
        emit({"v": 1, "cmd": "preset_list", "presets": names})

    def apply_preset(self, item, name):
        """Apply a .drx look to the current clip. Returns True when applied
        (so the caller can refresh its shadow-state handle)."""
        path = os.path.join(LOOKS_DIR, name + ".drx")
        if not os.path.isfile(path):
            emit({"v": 1, "cmd": "preset_applied", "name": name, "ok": False,
                  "reason": "Preset file not found — refresh the list"})
            return False

        # Same rule as wheel input: grading while bypassed is invisible.
        if self.node_bypassed and self._set_node_enabled(item, True):
            self.node_bypassed = False

        try:
            graph = item.GetNodeGraph()
            if graph is None:
                emit({"v": 1, "cmd": "preset_applied", "name": name, "ok": False,
                      "reason": "Clip has no node graph"})
                return False
            ok = bool(graph.ApplyGradeFromDRX(path, 0))  # 0 = no keyframes
            # WORKAROUND for a Resolve macOS API bug: a graph handle obtained
            # BEFORE ApplyGradeFromDRX can crash Resolve if used again
            # afterwards. Re-fetch immediately and drop both handles so
            # nothing stale can leak into later calls.
            graph = item.GetNodeGraph()
            del graph
        except Exception as exc:
            log("ApplyGradeFromDRX failed: %s" % exc)
            emit({"v": 1, "cmd": "preset_applied", "name": name, "ok": False,
                  "reason": "Resolve error applying preset: %s" % exc})
            return False

        if not ok:
            emit({"v": 1, "cmd": "preset_applied", "name": name, "ok": False,
                  "reason": "Resolve rejected the preset"})
            return False

        # The DRX is now the base look; the wheel/knobs become a neutral trim
        # layer on top of it. Reset the shadow state (without calling SetCDL,
        # which would stomp the look's own node 1 CDL) and tell the phone so
        # its readouts zero out.
        state = self.state_for(item)
        state.update(USER_DEFAULTS)
        self.announce(True, item=item, state=state, force=True)
        emit({"v": 1, "cmd": "preset_applied", "name": name, "ok": True})
        log("applied preset %r" % name)
        return True

    def grab_still(self, timeline):
        try:
            ok = timeline.GrabStillFromCurrentVideoClip() is not None
        except Exception as exc:
            log("GrabStillFromCurrentVideoClip failed: %s" % exc)
            ok = False
        emit({"v": 1, "cmd": "still_grabbed", "ok": ok})

    def apply_cdl(self, item, state):
        try:
            return bool(item.SetCDL(compose_cdl(state)))
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
            def bal(key):
                vec = state.get(key, (0.0, 0.0))
                return [round(vec[0], 6), round(vec[1], 6)]

            emit({
                "v": 1,
                "cmd": "color_state",
                "available": True,
                "clip": clip_name,
                "lift": round(state["lift_m"], 6),
                "gamma": round(state["gamma_m"], 6),
                "gain": round(state["gain_m"], 6),
                "sat": round(state["sat"], 6),
                "temp": round(state["temp"], 6),
                "tint": round(state["tint"], 6),
                "contrast": round(state["contrast"], 6),
                "pivot": round(state["pivot"], 6),
                "lift_bal": bal("bal_lift"),
                "gamma_bal": bal("bal_gamma"),
                "gain_bal": bal("bal_gain"),
            })
        else:
            emit({"v": 1, "cmd": "color_state", "available": False, "reason": reason})


# ---------------------------------------------------------------------------
# Main loop: stdin reader thread + rate-limited batch worker
# ---------------------------------------------------------------------------

def main():
    commands = queue.Queue()
    sentinel = object()
    engine = ColorEngine()

    def read_stdin():
        for line in sys.stdin:
            line = line.strip()
            if not line:
                continue
            try:
                cmd = json.loads(line)
            except ValueError:
                log("ignoring malformed JSON: %s" % line)
                continue
            if cmd.get("cmd") == "bypass":
                # Momentary control: handle right here, skipping the rate
                # limiter, so hold-to-compare feels instant.
                engine.handle_bypass(bool(cmd.get("enabled", True)))
            else:
                commands.put(cmd)
        commands.put(sentinel)  # stdin closed: the helper went away

    threading.Thread(target=read_stdin, daemon=True).start()

    log("resolve_bridge started (python %s)" % sys.version.split()[0])
    try:
        os.makedirs(LOOKS_DIR, exist_ok=True)
        log("looks folder: %s" % LOOKS_DIR)
    except OSError as exc:
        log("could not create looks folder %s: %s" % (LOOKS_DIR, exc))
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

    # Never exit with the node silently bypassed.
    if engine.node_bypassed:
        engine.handle_bypass(True)
    log("stdin closed, exiting")


if __name__ == "__main__":
    main()
