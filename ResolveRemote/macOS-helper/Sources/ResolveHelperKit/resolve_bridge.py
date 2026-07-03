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

# Default node when no set_node has been received yet.
NODE_INDEX = "1"

# Look presets: every .drx file in this folder is a preset; the filename
# (without extension) is the button name on the phone. The folder is the
# management UI — the sidecar re-scans it on every list request.
LOOKS_DIR = os.path.expanduser("~/ResolveRemote/Looks")

# Fusion comp presets (Phase 17): every .comp file in this folder is an
# importable preset chip on the iPad, and parameterless exports auto-name
# into it — same folder-is-the-UI rule as LOOKS_DIR. Env override exists
# so the test harness can sandbox it.
COMPS_DIR = (os.environ.get("RESOLVE_REMOTE_COMPS_DIR")
             or os.path.expanduser("~/ResolveRemote/Comps"))

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


# Capability-probe feature status values (Phase 11).
STATUS_SUPPORTED = "supported"
STATUS_UNSUPPORTED = "unsupported"
STATUS_UNKNOWN = "unknown"
STATUS_ERROR = "error"


# Phase 16 Fusion smoke tests: the ONLY tool ids fusion_add_tool_test may
# create, and the ONLY tool inputs fusion_set_input_test may set. `kinds`
# are substrings matched against the tool's registry id (TOOLS_RegID);
# `coerce` is how the wire value (always a string) becomes a typed value —
# a value that can't be coerced is refused (unsupported_input_type), never
# guessed.
FUSION_TOOL_ALLOWLIST = ("TextPlus", "Background", "Merge", "Transform")
FUSION_INPUT_ALLOWLIST = {
    "StyledText": {"kinds": ("Text",), "coerce": "str"},
    "Size": {"kinds": ("Transform",), "coerce": "float"},
    "Center": {"kinds": ("Transform",), "coerce": "point"},
}


# Phase 17/18 production Fusion surface. Tool registry ids the iPad's
# TOOLS grid may add, matched EXACTLY against the id sent ("Transform"
# must not substring-match "PlanarTransform"). Hardware pass on Resolve
# 21.0.0b confirmed everything in the original 16 EXCEPT PlanarTracker
# (Resolve refuses to create it via scripting — kept listed for future
# versions). Phase 18 expands this to the full curated catalog behind the
# iPad's customisable grid; a wrong id still fails clean (resolve_error).
FUSION_ADD_TOOL_IDS = (
    # Generators / text
    "Background", "FastNoise", "TextPlus", "Text3D",
    # Composite
    "Merge", "Dissolve",
    # Transform
    "Transform", "Resize", "Crop", "Letterbox", "DVE", "CameraShake",
    # Tracking
    "Tracker", "PlanarTracker", "PlanarTransform",
    # Masks
    "RectangleMask", "EllipseMask", "PolylineMask", "BSplineMask",
    "TriangleMask", "WandMask",
    # Blur / sharpen
    "Blur", "DirectionalBlur", "Defocus", "Sharpen",
    # Light / effects
    "Glow", "SoftGlow", "Shadow", "Highlight",
    # Colour
    "ColorCorrector", "ColorCurves", "HueCurves", "BrightnessContrast",
    "ColorGain", "WhiteBalance", "ChannelBooleans", "Gamut",
    # Keying
    "DeltaKeyer", "ChromaKeyer", "LumaKeyer", "UltraKeyer", "MatteControl",
    # Paint / warp
    "Paint", "GridWarp", "Displace", "CornerPositioner",
    # Time / optics
    "TimeSpeed", "TimeStretcher", "LensDistort", "FilmGrain",
)

# Curated per-tool parameter map for the SELECTED PARAMETER knob:
# {regid: {input_id: (min, max, default, step-per-tick)}}. Deliberately
# small and honest — only inputs with well-known ids; anything else shows
# "no mapped parameters" instead of guessing.
FUSION_PARAM_MAP = {
    "Transform": {
        "Size": (0.0, 5.0, 1.0, 0.01),
        "Angle": (-360.0, 360.0, 0.0, 1.0),
    },
    "Merge": {
        "Blend": (0.0, 1.0, 1.0, 0.005),
        "Size": (0.0, 5.0, 1.0, 0.01),
    },
    "TextPlus": {
        "Size": (0.0, 0.5, 0.08, 0.001),
    },
    "Background": {
        "TopLeftRed": (0.0, 1.0, 0.0, 0.005),
        "TopLeftGreen": (0.0, 1.0, 0.0, 0.005),
        "TopLeftBlue": (0.0, 1.0, 0.0, 0.005),
    },
    "Blur": {
        "XBlurSize": (0.0, 100.0, 10.0, 0.5),
    },
    "Glow": {
        "Gain": (0.0, 10.0, 1.0, 0.02),
        "XGlowSize": (0.0, 100.0, 10.0, 0.5),
    },
    "SoftGlow": {
        "Gain": (0.0, 10.0, 1.0, 0.02),
        "XGlowSize": (0.0, 100.0, 10.0, 0.5),
    },
    "ColorCorrector": {
        "MasterRGBGain": (0.0, 2.0, 1.0, 0.005),
    },
}

# Which tools the XY CONTROL pad drives (regid -> point input id), and the
# per-axis clamp (allows moving content off-screen, but not into orbit).
FUSION_XY_MAP = {"Transform": "Center", "Merge": "Center", "TextPlus": "Center"}
CLAMP_FUSION_CENTER = (-0.5, 1.5)
FUSION_CENTER_DEFAULT = [0.5, 0.5]

# Fusion knob/XY commands that ride the rate-limited batch worker instead
# of the instant reader thread.
FUSION_BATCHED_CMDS = ("fusion_param_delta", "fusion_xy_delta", "fusion_param_reset")


def has_method(obj, name):
    """True if `obj` exposes a callable `name`. Resolve's bridge returns None
    (not AttributeError) for methods a given version doesn't have, so a plain
    getattr + callable check is the reliable presence test."""
    return obj is not None and callable(getattr(obj, name, None))


def feature_from_method(obj, name):
    """Map method presence to a feature status. `unknown` when the owning
    object itself is missing (we couldn't even look), else supported/unsupported."""
    if obj is None:
        return STATUS_UNKNOWN
    return STATUS_SUPPORTED if callable(getattr(obj, name, None)) else STATUS_UNSUPPORTED


def safe_call(fn, default=None):
    """Call `fn` and swallow any error, returning `default`. Used so one flaky
    Resolve call never aborts the probe."""
    try:
        return fn()
    except Exception:
        return default


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


def compose_cdl(params, node_index=NODE_INDEX):
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
        "NodeIndex": node_index,
        "Slope": triplet(slope),
        "Offset": triplet(offset),
        "Power": triplet(power),
        "Saturation": "%.6f" % clamped(params["sat"], CLAMP_SAT),
    }


def emit(obj):
    """One JSON reply line on stdout (the helper forwards it to the phone)."""
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


def emit_color_result(cmd, ok, message=None, reason=None, details=None):
    """Phase 14 smoke-test reply: one color_action_result line."""
    payload = {"v": 1, "type": "color_action_result", "cmd": cmd, "ok": bool(ok)}
    if message is not None:
        payload["message"] = message
    if reason is not None:
        payload["reason"] = reason
    if details is not None:
        payload["details"] = details
    emit(payload)


def emit_fusion_result(cmd, ok, message=None, reason=None, page=None, details=None):
    """Phase 15/16 Fusion action reply: one fusion_action_result line."""
    payload = {"v": 1, "type": "fusion_action_result", "cmd": cmd, "ok": bool(ok)}
    if message is not None:
        payload["message"] = message
    if reason is not None:
        payload["reason"] = reason
    if page is not None:
        payload["page"] = page
    if details is not None:
        payload["details"] = details
    emit(payload)


def emit_command_rejected(cmd, reason, message=None):
    """A guarded command was refused (e.g. destructive without confirm)."""
    payload = {"v": 1, "type": "command_rejected", "cmd": cmd, "reason": reason}
    if message is not None:
        payload["message"] = message
    emit(payload)


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
        self.states = {}            # (clip unique id, node index) -> params dict
        self.active_node = 1        # stepper-selected node, clamped per clip
        self.last_available = None  # tri-state: None / True / False
        self.bypassed_node = None   # node index currently bypassed, or None
        # Bypass runs on the reader thread, applies on the worker — one lock
        # guards all Resolve API access.
        self.lock = threading.Lock()

    def state_for(self, item):
        """Shadow state for (current clip, active node)."""
        key = (item.GetUniqueId(), self.active_node)
        return self.states.setdefault(key, fresh_state())

    def fresh_node_count(self, item):
        """Fresh GetNumNodes() for this single operation — node counts and
        graph handles are NEVER cached beyond one command, so nodes added or
        deleted in Resolve are seen immediately. Clamps the active node down
        if the tree shrank."""
        count = self._node_count(item)
        if self.active_node > count:
            log("active node clamped %d -> %d (tree shrank)" % (self.active_node, count))
            self.active_node = count
        if self.active_node < 1:
            self.active_node = 1
        return count

    def _node_count(self, item):
        try:
            graph = item.GetNodeGraph()
            if graph is not None:
                # The bridge returns None (not AttributeError) for methods
                # the running Resolve doesn't have — check callability.
                getter = getattr(graph, "GetNumNodes", None)
                if callable(getter):
                    count = getter()
                    if isinstance(count, (int, float)) and count >= 1:
                        return int(count)
        except Exception as exc:
            log("GetNumNodes failed: %s" % exc)
        return 1

    # -- capability probe (Phase 11) ----------------------------------------

    def handle_capability_probe(self, cmd):
        """Introspect the installed Resolve's scripting API and emit one
        capability_state line. Runs on the reader thread (like bypass), not
        through the colour batch, so it works with no project/clip and never
        blocks grading. Every check is defensive: a failure records an
        error/warning but never aborts the probe."""
        with self.lock:
            warnings = []
            errors = []
            features = {}

            connected = self.session.connect()
            resolve = self.session.resolve if connected else None

            product_name = None
            version_string = None
            current_page = None
            if resolve is not None:
                product_name = safe_call(lambda: resolve.GetProductName())
                version_string = (
                    safe_call(lambda: resolve.GetVersionString())
                    or safe_call(lambda: resolve.GetVersion())
                )
                if isinstance(version_string, (list, tuple)):
                    version_string = ".".join(str(part) for part in version_string)
                current_page = safe_call(lambda: resolve.GetCurrentPage())
            elif self.session.reason:
                warnings.append(self.session.reason)

            timeline, item, reason = (None, None, None)
            if resolve is not None:
                timeline, item, reason = self.session.current_context()
                if item is None and reason:
                    warnings.append(reason)

            # Edit / timeline
            features["open_page"] = feature_from_method(resolve, "OpenPage")
            features["current_timecode"] = feature_from_method(timeline, "GetCurrentTimecode")
            features["set_timecode"] = feature_from_method(timeline, "SetCurrentTimecode")
            features["markers"] = feature_from_method(timeline, "GetMarkers")
            features["thumbnail"] = feature_from_method(timeline, "GetCurrentClipThumbnailImage")
            features["track_control"] = feature_from_method(timeline, "SetTrackEnable")

            # Colour / nodes / stills / LUTs (need the current video item + graph)
            features["cdl"] = feature_from_method(item, "SetCDL")
            features["grab_still"] = feature_from_method(timeline, "GrabStill")
            graph = None
            if has_method(item, "GetNodeGraph"):
                graph = safe_call(lambda: item.GetNodeGraph())
                features["node_graph"] = STATUS_SUPPORTED if graph is not None else STATUS_UNKNOWN
            else:
                features["node_graph"] = feature_from_method(item, "GetNodeGraph")
            features["apply_drx"] = feature_from_method(graph, "ApplyGradeFromDRX")
            features["set_lut"] = feature_from_method(graph, "SetLUT")
            features["reset_grades"] = feature_from_method(graph, "ResetAllGrades")
            # Phase 19 — read-only node-FX inventory. The API can only READ
            # tools in a colour node, never add/modify them.
            features["node_tools"] = feature_from_method(graph, "GetToolsInNode")

            # Studio AI — absence from scripting doesn't prove the feature is
            # missing, only that it isn't scriptable here, so default unknown.
            # Never invoke these during a probe.
            features["voice_isolation"] = self._probe_ai_presence(
                [(timeline, "SetVoiceIsolation"), (resolve, "SetVoiceIsolation")])
            features["magic_mask"] = self._probe_ai_presence(
                [(item, "CreateMagicMask"), (graph, "CreateMagicMask")])
            features["smart_reframe"] = self._probe_ai_presence(
                [(item, "SmartReframe"), (graph, "SmartReframe")])

            # Photo page — do NOT switch the user's page to test it.
            features["photo_page"] = STATUS_UNKNOWN
            warnings.append(
                "Photo page not probed to avoid switching your page; "
                "use a keyboard fallback if needed."
            )

            payload = {
                "v": 1,
                "type": "capability_state",
                "resolve_connected": connected,
                "product_name": product_name,
                "version_string": version_string,
                "current_page": current_page,
                "current_project": timeline is not None or bool(
                    resolve is not None and safe_call(
                        lambda: resolve.GetProjectManager().GetCurrentProject()) is not None),
                "current_timeline": timeline is not None,
                "current_video_item": item is not None,
                "features": features,
                "warnings": warnings,
                "errors": errors,
            }
            emit(payload)
            log("capability probe: connected=%s product=%s version=%s page=%s"
                % (connected, product_name, version_string, current_page))

    def _probe_ai_presence(self, candidates):
        """Return supported if any (obj, method) pair exists, else unknown —
        AI functions absent from scripting are reported unknown, not
        unsupported, and are never called."""
        for obj, name in candidates:
            if has_method(obj, name):
                return STATUS_SUPPORTED
        return STATUS_UNKNOWN

    # -- Fusion capability probe (Phase 15) ----------------------------------

    def handle_fusion_probe(self, cmd):
        """Introspect what Fusion exposes to scripting and emit one
        fusion_capability_state line. Same contract as the capability probe:
        runs on the reader thread, works with no project/clip, and never
        mutates anything. Invocation tiers:
          1. anything mutating (open page, add/import/export/rename/delete
             comp, add tool, set input) is reported by PRESENCE ONLY;
          2. read-only calls (Fusion(), comp count, comp names, current comp)
             are invoked, safe_call-wrapped;
          3. comp internals (tool list, active tool) are only invoked while
             the Fusion page is already open — the probe never switches the
             user's page (photo_page rule)."""
        with self.lock:
            warnings = []
            errors = []
            features = {}

            connected = self.session.connect()
            resolve = self.session.resolve if connected else None

            product_name = None
            version_string = None
            current_page = None
            if resolve is not None:
                product_name = safe_call(lambda: resolve.GetProductName())
                version_string = (
                    safe_call(lambda: resolve.GetVersionString())
                    or safe_call(lambda: resolve.GetVersion())
                )
                if isinstance(version_string, (list, tuple)):
                    version_string = ".".join(str(part) for part in version_string)
                current_page = safe_call(lambda: resolve.GetCurrentPage())
            elif self.session.reason:
                warnings.append(self.session.reason)

            timeline, item, reason = (None, None, None)
            if resolve is not None:
                timeline, item, reason = self.session.current_context()
                if item is None and reason:
                    warnings.append(reason)

            # Tier 1 — page switching, presence only (open_fusion_page is a
            # separate explicit command; the probe never calls it).
            features["open_fusion_page"] = feature_from_method(resolve, "OpenPage")

            # Tier 2 — the FusionScript object; resolve.Fusion() is read-only.
            fusion = None
            if has_method(resolve, "Fusion"):
                fusion = safe_call(lambda: resolve.Fusion())
                features["fusion_object"] = (
                    STATUS_SUPPORTED if fusion is not None else STATUS_UNKNOWN)
            else:
                features["fusion_object"] = feature_from_method(resolve, "Fusion")

            # Tier 2 — TimelineItem comp management. Count and name list are
            # read-only and invoked; everything mutating is presence only.
            comp_count = None
            comp_names = None
            if has_method(item, "GetFusionCompCount"):
                comp_count = safe_call(lambda: item.GetFusionCompCount())
                if isinstance(comp_count, float):
                    comp_count = int(comp_count)
                features["comp_count"] = (
                    STATUS_SUPPORTED if isinstance(comp_count, int) else STATUS_ERROR)
                if not isinstance(comp_count, int):
                    comp_count = None
            else:
                features["comp_count"] = feature_from_method(item, "GetFusionCompCount")
            if has_method(item, "GetFusionCompNameList"):
                comp_names = safe_call(lambda: item.GetFusionCompNameList())
                if isinstance(comp_names, dict):
                    # FusionScript sometimes hands back Lua-style tables.
                    comp_names = [comp_names[key] for key in sorted(comp_names)]
                if isinstance(comp_names, (list, tuple)):
                    comp_names = [str(name) for name in comp_names]
                    features["comp_names"] = STATUS_SUPPORTED
                else:
                    comp_names = None
                    features["comp_names"] = STATUS_ERROR
            else:
                features["comp_names"] = feature_from_method(item, "GetFusionCompNameList")
            features["get_comp_by_index"] = feature_from_method(item, "GetFusionCompByIndex")
            features["load_comp"] = feature_from_method(item, "LoadFusionCompByName")
            features["add_comp"] = feature_from_method(item, "AddFusionComp")
            features["import_comp"] = feature_from_method(item, "ImportFusionComp")
            features["export_comp"] = feature_from_method(item, "ExportFusionComp")
            features["rename_comp"] = feature_from_method(item, "RenameFusionCompByName")
            features["delete_comp"] = feature_from_method(item, "DeleteFusionCompByName")
            warnings.append(
                "Comp-mutating methods (add/import/export/rename/delete comp, "
                "add tool, set input) are reported by presence only; the probe "
                "never invokes them."
            )

            # Tier 3 — comp internals, only with the Fusion page already open.
            current_comp = None
            tool_count = None
            features["tool_list"] = STATUS_UNKNOWN
            features["active_tool"] = STATUS_UNKNOWN
            features["add_tool"] = STATUS_UNKNOWN
            features["set_tool_input"] = STATUS_UNKNOWN
            comp = None
            if fusion is not None and has_method(fusion, "GetCurrentComp"):
                comp = safe_call(lambda: fusion.GetCurrentComp())
                current_comp = comp is not None
            if comp is None and isinstance(comp_count, int) and comp_count >= 1 \
                    and has_method(item, "GetFusionCompByIndex"):
                comp = safe_call(lambda: item.GetFusionCompByIndex(1))
            if current_page == "fusion" and comp is not None:
                tools = None
                if has_method(comp, "GetToolList"):
                    tools = safe_call(lambda: comp.GetToolList(False))
                    if isinstance(tools, dict):
                        tools = [tools[key] for key in sorted(tools)]
                    if isinstance(tools, (list, tuple)):
                        tool_count = len(tools)
                        features["tool_list"] = STATUS_SUPPORTED
                    else:
                        tools = None
                        features["tool_list"] = STATUS_ERROR
                else:
                    features["tool_list"] = STATUS_UNSUPPORTED
                # ActiveTool is an attribute and None is a valid "nothing
                # selected" answer — only an exception leaves it unknown.
                missing = object()
                active = safe_call(lambda: getattr(comp, "ActiveTool", None), missing)
                if active is not missing:
                    features["active_tool"] = STATUS_SUPPORTED
                features["add_tool"] = (
                    STATUS_SUPPORTED if has_method(comp, "AddTool") else STATUS_UNSUPPORTED)
                if tools:
                    features["set_tool_input"] = (
                        STATUS_SUPPORTED if has_method(tools[0], "SetInput")
                        else STATUS_UNKNOWN)
            else:
                warnings.append(
                    "Fusion comp internals (tools, parameters) are only proven "
                    "while the Fusion page is open — open it and re-probe. "
                    "The probe never switches your page."
                )

            payload = {
                "v": 1,
                "type": "fusion_capability_state",
                "resolve_connected": connected,
                "product_name": product_name,
                "version_string": version_string,
                "current_page": current_page,
                "current_project": timeline is not None or bool(
                    resolve is not None and safe_call(
                        lambda: resolve.GetProjectManager().GetCurrentProject()) is not None),
                "current_timeline": timeline is not None,
                "current_video_item": item is not None,
                "fusion_object": fusion is not None,
                "comp_count": comp_count,
                "comp_names": comp_names,
                "current_comp": current_comp,
                "tool_count": tool_count,
                "features": features,
                "warnings": warnings,
                "errors": errors,
            }
            emit(payload)
            log("fusion probe: connected=%s page=%s comps=%s tools=%s"
                % (connected, current_page, comp_count, tool_count))

    def handle_open_fusion_page(self, cmd):
        """The single mutating Fusion action this phase: switch Resolve to
        the Fusion page. Success is verified by re-reading GetCurrentPage."""
        with self.lock:
            if not self.session.connect():
                emit_fusion_result("open_fusion_page", False,
                                   reason="no_resolve",
                                   message=self.session.reason)
                return
            resolve = self.session.resolve
            if not has_method(resolve, "OpenPage"):
                emit_fusion_result(
                    "open_fusion_page", False, reason="unsupported",
                    message="This Resolve does not expose OpenPage to scripting")
                return
            try:
                result = resolve.OpenPage("fusion")
                page = safe_call(lambda: resolve.GetCurrentPage())
                ok = bool(result) or page == "fusion"
                emit_fusion_result(
                    "open_fusion_page", ok, page=page,
                    reason=None if ok else "resolve_error",
                    message=None if ok else "Resolve refused to open the Fusion page")
                log("open_fusion_page: ok=%s page=%s" % (ok, page))
            except Exception as exc:
                # Resolve most likely quit; drop the handle so the next
                # command attempts a fresh connection.
                self.session.resolve = None
                emit_fusion_result("open_fusion_page", False,
                                   reason="resolve_error", message=str(exc))
                log("open_fusion_page failed: %s" % exc)

    # -- Fusion action smoke tests (Phase 16) --------------------------------
    #
    # These prove that the methods the Phase-15 probe found actually execute.
    # Rules: mutating commands require confirm:true; tool creation and input
    # setting are allowlisted; import/export need explicit paths; delete is
    # status-only. A Fusion API failure emits a clean fusion_action_result —
    # it never kills the sidecar.

    def handle_fusion_action(self, cmd):
        """Dispatch one mode:"fusion" smoke-test command on the reader
        thread (instant, no colour-batch coupling)."""
        name = cmd.get("cmd")
        handlers = {
            "fusion_context": self._fusion_cmd_context,
            "fusion_list_comps": self._fusion_cmd_list_comps,
            "fusion_list_tools": self._fusion_cmd_list_tools,
            "fusion_active_tool": self._fusion_cmd_active_tool,
            "fusion_export_comp": self._fusion_cmd_export_comp,
            "fusion_import_comp": self._fusion_cmd_import_comp,
            "fusion_add_comp": self._fusion_cmd_add_comp,
            "fusion_rename_comp": self._fusion_cmd_rename_comp,
            "fusion_add_tool_test": self._fusion_cmd_add_tool_test,
            "fusion_set_input_test": self._fusion_cmd_set_input_test,
            "fusion_delete_comp_status": self._fusion_cmd_delete_comp_status,
            # Phase 17 — production Fusion surface
            "fusion_status": self._fusion_cmd_status,
            "fusion_add_tool": self._fusion_cmd_add_tool,
            "fusion_select_tool": self._fusion_cmd_select_tool,
            "fusion_load_comp": self._fusion_cmd_load_comp,
            "fusion_delete_comp": self._fusion_cmd_delete_comp,
            "fusion_list_comp_files": self._fusion_cmd_list_comp_files,
            "fusion_import_comp_file": self._fusion_cmd_import_comp_file,
        }
        handler = handlers.get(name)
        if handler is None:
            emit_command_rejected(name or "?", "unknown_command",
                                  "Unknown fusion command")
            return
        with self.lock:
            try:
                handler(cmd)
            except Exception as exc:
                log("fusion action %s failed: %s" % (name, exc))
                emit_fusion_result(name, False, reason="resolve_error",
                                   message=str(exc))

    def _fusion_objects(self):
        """Shared guard: (resolve, timeline, item, fusion, comp, reason).
        `comp` is the current Fusion comp when one is open, else the clip's
        first saved comp; any element may be None, with `reason` describing
        the first gap."""
        if not self.session.connect():
            return None, None, None, None, None, self.session.reason
        resolve = self.session.resolve
        timeline, item, reason = self.session.current_context()
        fusion = None
        if has_method(resolve, "Fusion"):
            fusion = safe_call(lambda: resolve.Fusion())
        comp = None
        if fusion is not None and has_method(fusion, "GetCurrentComp"):
            comp = safe_call(lambda: fusion.GetCurrentComp())
        if comp is None and item is not None \
                and has_method(item, "GetFusionCompByIndex"):
            count = self._fusion_comp_count(item)
            if isinstance(count, int) and count >= 1:
                comp = safe_call(lambda: item.GetFusionCompByIndex(1))
        return resolve, timeline, item, fusion, comp, reason

    def _fusion_comp_count(self, item):
        if not has_method(item, "GetFusionCompCount"):
            return None
        count = safe_call(lambda: item.GetFusionCompCount())
        if isinstance(count, float):
            count = int(count)
        return count if isinstance(count, int) else None

    def _fusion_comp_names(self, item):
        if not has_method(item, "GetFusionCompNameList"):
            return None
        names = safe_call(lambda: item.GetFusionCompNameList())
        if isinstance(names, dict):
            names = [names[key] for key in sorted(names)]
        if isinstance(names, (list, tuple)):
            return [str(name) for name in names]
        return None

    def _fusion_tools(self, comp):
        """Raw tool objects from comp.GetToolList (read-only), or None."""
        if not has_method(comp, "GetToolList"):
            return None
        tools = safe_call(lambda: comp.GetToolList(False))
        if isinstance(tools, dict):
            tools = [tools[key] for key in sorted(tools)]
        return list(tools) if isinstance(tools, (list, tuple)) else None

    def _tool_entry(self, tool):
        """{name, type} for one tool, defensively (attrs may be missing)."""
        attrs = {}
        if has_method(tool, "GetAttrs"):
            attrs = safe_call(lambda: tool.GetAttrs(), {}) or {}
        if not isinstance(attrs, dict):
            attrs = {}
        name = attrs.get("TOOLS_Name") or safe_call(lambda: getattr(tool, "Name", None))
        reg = attrs.get("TOOLS_RegID") or safe_call(lambda: getattr(tool, "ID", None))
        return {"name": str(name) if name is not None else "?",
                "type": str(reg) if reg is not None else "?"}

    def _require_confirm(self, cmd):
        """Guard for mutating smoke tests; rejects and returns False when
        confirm:true is absent."""
        if cmd.get("confirm") is True:
            return True
        name = cmd.get("cmd", "?")
        emit_command_rejected(name, "confirmation_required",
                              "%s requires confirm:true" % name)
        return False

    # -- read-only smoke tests ----------------------------------------------

    def _fusion_cmd_context(self, cmd):
        resolve, timeline, item, fusion, comp, reason = self._fusion_objects()
        if resolve is None:
            emit_fusion_result("fusion_context", False, reason="no_resolve",
                               message=reason)
            return
        tools = self._fusion_tools(comp) if comp is not None else None
        details = {
            "current_page": safe_call(lambda: resolve.GetCurrentPage()),
            "current_project": timeline is not None,
            "current_timeline": timeline is not None,
            "current_video_item": item is not None,
            "fusion_object": fusion is not None,
            "comp_count": self._fusion_comp_count(item),
            "comp_names": self._fusion_comp_names(item),
            "tool_count": len(tools) if tools is not None else None,
        }
        ok = item is not None
        emit_fusion_result(
            "fusion_context", ok,
            message="Fusion context available" if ok else (reason or "No clip"),
            reason=None if ok else "no_clip",
            details=details)

    def _fusion_cmd_list_comps(self, cmd):
        resolve, _, item, _, _, reason = self._fusion_objects()
        if resolve is None:
            emit_fusion_result("fusion_list_comps", False, reason="no_resolve",
                               message=reason)
            return
        if item is None:
            emit_fusion_result("fusion_list_comps", False, reason="no_clip",
                               message=reason)
            return
        count = self._fusion_comp_count(item)
        names = self._fusion_comp_names(item)
        if count is None and names is None:
            emit_fusion_result("fusion_list_comps", False, reason="unsupported",
                               message="This clip exposes no Fusion comp methods")
            return
        emit_fusion_result("fusion_list_comps", True,
                           message="Listed Fusion comps",
                           details={"comp_count": count, "comp_names": names})

    def _fusion_cmd_list_tools(self, cmd):
        resolve, _, item, _, comp, reason = self._fusion_objects()
        if resolve is None:
            emit_fusion_result("fusion_list_tools", False, reason="no_resolve",
                               message=reason)
            return
        if comp is None:
            emit_fusion_result(
                "fusion_list_tools", False, reason="no_comp",
                message=reason or "No Fusion comp available — open the Fusion "
                                  "page on a clip with a comp")
            return
        tools = self._fusion_tools(comp)
        if tools is None:
            emit_fusion_result("fusion_list_tools", False, reason="unsupported",
                               message="GetToolList is unavailable on this comp")
            return
        entries = [self._tool_entry(tool) for tool in tools]
        emit_fusion_result("fusion_list_tools", True,
                           message="Listed Fusion tools",
                           details={"tool_count": len(entries), "tools": entries})

    def _fusion_cmd_active_tool(self, cmd):
        resolve, _, item, _, comp, reason = self._fusion_objects()
        if resolve is None:
            emit_fusion_result("fusion_active_tool", False, reason="no_resolve",
                               message=reason)
            return
        if comp is None:
            emit_fusion_result("fusion_active_tool", False, reason="no_comp",
                               message=reason or "No Fusion comp available")
            return
        missing = object()
        active = safe_call(lambda: getattr(comp, "ActiveTool", None), missing)
        if active is missing:
            emit_fusion_result("fusion_active_tool", False,
                               reason="resolve_error",
                               message="Reading ActiveTool failed")
            return
        # No selected tool is a valid answer, not a failure.
        emit_fusion_result(
            "fusion_active_tool", True,
            message="Active tool: %s" % (self._tool_entry(active)["name"]
                                         if active is not None else "none selected"),
            details={"active_tool": self._tool_entry(active)
                     if active is not None else None})

    def _fusion_cmd_delete_comp_status(self, cmd):
        """Status only — reports whether DeleteFusionCompByName exists.
        NOTHING is deleted in this phase."""
        resolve, _, item, _, _, reason = self._fusion_objects()
        if resolve is None:
            emit_fusion_result("fusion_delete_comp_status", False,
                               reason="no_resolve", message=reason)
            return
        emit_fusion_result(
            "fusion_delete_comp_status", True,
            message="Delete comp is status-only in this phase; nothing was deleted",
            details={"delete_comp": feature_from_method(item, "DeleteFusionCompByName")})

    # -- path-taking smoke tests --------------------------------------------

    def _fusion_cmd_export_comp(self, cmd):
        path = str(cmd.get("export_path") or "").strip()
        if path:
            path = os.path.expanduser(path)
            parent = os.path.dirname(path) or "."
            if not os.path.isdir(parent):
                emit_fusion_result("fusion_export_comp", False, reason="invalid_path",
                                   message="Parent folder does not exist: %s" % parent)
                return
        resolve, _, item, _, _, reason = self._fusion_objects()
        if resolve is None:
            emit_fusion_result("fusion_export_comp", False, reason="no_resolve",
                               message=reason)
            return
        if item is None:
            emit_fusion_result("fusion_export_comp", False, reason="no_clip",
                               message=reason)
            return
        if not has_method(item, "ExportFusionComp"):
            emit_fusion_result("fusion_export_comp", False, reason="unsupported",
                               message="ExportFusionComp is unavailable")
            return
        # The API exports by comp index (no "current comp index" getter);
        # default to the first comp.
        try:
            index = int(cmd.get("index") or 1)
        except (TypeError, ValueError):
            emit_fusion_result("fusion_export_comp", False, reason="invalid_index",
                               message="index must be a number")
            return
        if not path:
            # No path (Phase 17): auto-name into the comps folder so the
            # iPad never needs a Mac path typed in.
            names = self._fusion_comp_names(item) or []
            base = names[index - 1] if 1 <= index <= len(names) else "Comp%d" % index
            safe = "".join(ch if ch.isalnum() or ch in "-_ " else "_"
                           for ch in base).strip() or "Comp"
            path = os.path.join(
                COMPS_DIR, "%s_%s.comp" % (safe, time.strftime("%Y%m%d-%H%M%S")))
        result = item.ExportFusionComp(path, index)
        ok = bool(result)
        log("fusion_export_comp: index=%d path=%s ok=%s" % (index, path, ok))
        emit_fusion_result(
            "fusion_export_comp", ok,
            message="Exported comp %d" % index if ok else "Resolve refused the export",
            reason=None if ok else "resolve_error",
            details={"export_path": path, "index": index})

    def _fusion_cmd_import_comp(self, cmd):
        if not self._require_confirm(cmd):
            return
        path = str(cmd.get("import_path") or "").strip()
        if not path:
            emit_fusion_result("fusion_import_comp", False, reason="missing_path",
                               message="fusion_import_comp requires import_path")
            return
        path = os.path.expanduser(path)
        if not os.path.isfile(path):
            emit_fusion_result("fusion_import_comp", False, reason="invalid_path",
                               message="No file at %s" % path)
            return
        resolve, _, item, _, _, reason = self._fusion_objects()
        if resolve is None:
            emit_fusion_result("fusion_import_comp", False, reason="no_resolve",
                               message=reason)
            return
        if item is None:
            emit_fusion_result("fusion_import_comp", False, reason="no_clip",
                               message=reason)
            return
        if not has_method(item, "ImportFusionComp"):
            emit_fusion_result("fusion_import_comp", False, reason="unsupported",
                               message="ImportFusionComp is unavailable")
            return
        comp = item.ImportFusionComp(path)
        ok = comp is not None
        log("fusion_import_comp: path=%s ok=%s" % (path, ok))
        emit_fusion_result(
            "fusion_import_comp", ok,
            message="Imported comp" if ok else "Resolve refused the import",
            reason=None if ok else "resolve_error",
            details={"import_path": path,
                     "comp_count": self._fusion_comp_count(item),
                     "comp_names": self._fusion_comp_names(item)})

    # -- comp-mutating smoke tests ------------------------------------------

    def _fusion_cmd_add_comp(self, cmd):
        if not self._require_confirm(cmd):
            return
        resolve, _, item, _, _, reason = self._fusion_objects()
        if resolve is None:
            emit_fusion_result("fusion_add_comp", False, reason="no_resolve",
                               message=reason)
            return
        if item is None:
            emit_fusion_result("fusion_add_comp", False, reason="no_clip",
                               message=reason)
            return
        if not has_method(item, "AddFusionComp"):
            emit_fusion_result("fusion_add_comp", False, reason="unsupported",
                               message="AddFusionComp is unavailable")
            return
        comp = item.AddFusionComp()
        ok = comp is not None
        log("fusion_add_comp: ok=%s" % ok)
        emit_fusion_result(
            "fusion_add_comp", ok,
            message="Added a Fusion comp" if ok else "Resolve refused to add a comp",
            reason=None if ok else "resolve_error",
            details={"comp_count": self._fusion_comp_count(item),
                     "comp_names": self._fusion_comp_names(item)})

    def _fusion_cmd_rename_comp(self, cmd):
        if not self._require_confirm(cmd):
            return
        new_name = str(cmd.get("name") or "").strip()
        if not new_name:
            emit_fusion_result("fusion_rename_comp", False, reason="missing_name",
                               message="fusion_rename_comp requires a non-empty name")
            return
        resolve, _, item, _, _, reason = self._fusion_objects()
        if resolve is None:
            emit_fusion_result("fusion_rename_comp", False, reason="no_resolve",
                               message=reason)
            return
        if item is None:
            emit_fusion_result("fusion_rename_comp", False, reason="no_clip",
                               message=reason)
            return
        names = self._fusion_comp_names(item)
        try:
            index = int(cmd.get("index"))
        except (TypeError, ValueError):
            emit_fusion_result("fusion_rename_comp", False, reason="invalid_index",
                               message="fusion_rename_comp requires a comp index (1-based)")
            return
        if not names or index < 1 or index > len(names):
            emit_fusion_result(
                "fusion_rename_comp", False, reason="invalid_index",
                message="No comp at index %d (clip has %d)" % (index, len(names or [])))
            return
        if not has_method(item, "RenameFusionCompByName"):
            emit_fusion_result("fusion_rename_comp", False, reason="unsupported",
                               message="RenameFusionCompByName is unavailable")
            return
        # The API renames by name, so the index is mapped through the list.
        old_name = names[index - 1]
        ok = bool(item.RenameFusionCompByName(old_name, new_name))
        log("fusion_rename_comp: %r -> %r ok=%s" % (old_name, new_name, ok))
        emit_fusion_result(
            "fusion_rename_comp", ok,
            message="Renamed %r to %r" % (old_name, new_name) if ok
                    else "Resolve refused the rename",
            reason=None if ok else "resolve_error",
            details={"comp_names": self._fusion_comp_names(item)})

    # -- tool-mutating smoke tests (allowlisted) ------------------------------

    def _fusion_cmd_add_tool_test(self, cmd):
        if not self._require_confirm(cmd):
            return
        tool_id = str(cmd.get("tool_id") or "").strip()
        if tool_id not in FUSION_TOOL_ALLOWLIST:
            emit_fusion_result(
                "fusion_add_tool_test", False, reason="tool_not_allowlisted",
                message="Only %s may be added by the smoke test"
                        % ", ".join(FUSION_TOOL_ALLOWLIST))
            return
        resolve, _, item, _, comp, reason = self._fusion_objects()
        if resolve is None:
            emit_fusion_result("fusion_add_tool_test", False, reason="no_resolve",
                               message=reason)
            return
        if comp is None:
            emit_fusion_result("fusion_add_tool_test", False, reason="no_comp",
                               message=reason or "No Fusion comp available")
            return
        if not has_method(comp, "AddTool"):
            emit_fusion_result("fusion_add_tool_test", False, reason="unsupported",
                               message="AddTool is unavailable on this comp")
            return
        tool = comp.AddTool(tool_id)
        ok = tool is not None
        log("fusion_add_tool_test: %s ok=%s" % (tool_id, ok))
        emit_fusion_result(
            "fusion_add_tool_test", ok,
            message="Added %s" % tool_id if ok
                    else "Resolve refused to add %s" % tool_id,
            reason=None if ok else "resolve_error",
            details={"tool": self._tool_entry(tool) if ok else None})

    def _fusion_cmd_set_input_test(self, cmd):
        if not self._require_confirm(cmd):
            return
        tool_name = str(cmd.get("tool_name") or "").strip()
        input_name = str(cmd.get("input_name") or "").strip()
        if not tool_name or not input_name:
            emit_fusion_result(
                "fusion_set_input_test", False, reason="missing_name",
                message="fusion_set_input_test requires tool_name and input_name")
            return
        rule = FUSION_INPUT_ALLOWLIST.get(input_name)
        if rule is None:
            emit_fusion_result(
                "fusion_set_input_test", False, reason="unsupported_input_type",
                message="Only %s may be set by the smoke test"
                        % ", ".join(sorted(FUSION_INPUT_ALLOWLIST)))
            return
        raw = cmd.get("value")
        value, coerce_error = self._coerce_input_value(rule["coerce"], raw)
        if coerce_error:
            emit_fusion_result("fusion_set_input_test", False,
                               reason="unsupported_input_type", message=coerce_error)
            return
        resolve, _, item, _, comp, reason = self._fusion_objects()
        if resolve is None:
            emit_fusion_result("fusion_set_input_test", False, reason="no_resolve",
                               message=reason)
            return
        if comp is None:
            emit_fusion_result("fusion_set_input_test", False, reason="no_comp",
                               message=reason or "No Fusion comp available")
            return
        tools = self._fusion_tools(comp) or []
        tool = None
        for candidate in tools:
            if self._tool_entry(candidate)["name"] == tool_name:
                tool = candidate
                break
        if tool is None:
            emit_fusion_result("fusion_set_input_test", False, reason="tool_not_found",
                               message="No tool named %r in the comp" % tool_name)
            return
        # The input must be on the right KIND of tool (StyledText on Text
        # tools, Size/Center on Transform) — never set blind.
        tool_type = self._tool_entry(tool)["type"]
        if not any(kind.lower() in tool_type.lower() for kind in rule["kinds"]):
            emit_fusion_result(
                "fusion_set_input_test", False, reason="unsupported_input_type",
                message="%s is only settable on %s tools (got %s)"
                        % (input_name, "/".join(rule["kinds"]), tool_type))
            return
        if not has_method(tool, "SetInput"):
            emit_fusion_result("fusion_set_input_test", False, reason="unsupported",
                               message="SetInput is unavailable on this tool")
            return
        tool.SetInput(input_name, value)
        log("fusion_set_input_test: %s.%s = %r" % (tool_name, input_name, value))
        emit_fusion_result(
            "fusion_set_input_test", True,
            message="Set %s on %s" % (input_name, tool_name),
            details={"tool_name": tool_name, "input_name": input_name,
                     "value": raw})

    @staticmethod
    def _coerce_input_value(kind, raw):
        """Wire values arrive as strings; coerce per allowlist rule. Returns
        (value, error_message) — a value that can't be coerced is refused,
        never guessed."""
        if raw is None:
            return None, "fusion_set_input_test requires value"
        text = str(raw)
        if kind == "str":
            return text, None
        if kind == "float":
            try:
                return float(text), None
            except ValueError:
                return None, "%r is not a number" % text
        if kind == "point":
            parts = [part.strip() for part in text.split(",")]
            try:
                if len(parts) != 2:
                    raise ValueError
                return [float(parts[0]), float(parts[1])], None
            except ValueError:
                return None, "%r is not an \"x,y\" point" % text
        return None, "No coercion rule for %s" % kind

    # -- Fusion control surface (Phase 17) ------------------------------------
    #
    # The wired iPad Fusion tab. The iPad owns tool selection by NAME (the
    # path Phase 16 proved); SetActiveTool is best-effort sugar. Knob/XY
    # deltas ride the 30Hz batch worker (coalesced per tool+param); each
    # applied batch emits one fusion_state, like color_state for colour.

    @staticmethod
    def _read_center(tool, input_name):
        """A point input's [x, y], tolerating Lua-style {1:x, 2:y} tables.
        None when the value isn't a readable point."""
        value = safe_call(lambda: tool.GetInput(input_name))
        if isinstance(value, dict):
            value = [value.get(1), value.get(2)]
        if (isinstance(value, (list, tuple)) and len(value) >= 2
                and all(isinstance(v, (int, float)) for v in value[:2])):
            return [float(value[0]), float(value[1])]
        return None

    def _fusion_tool_by_name(self, comp, tool_name):
        for tool in self._fusion_tools(comp) or []:
            if self._tool_entry(tool)["name"] == tool_name:
                return tool
        return None

    def _emit_fusion_state(self, resolve, item, comp, tool=None, reason=None):
        """One fusion_state line: comp context + the target tool's curated
        params for the iPad surface. `tool` is the param target (falls back
        to the comp's ActiveTool)."""
        available = comp is not None
        clip = None
        if item is not None and has_method(item, "GetName"):
            clip = safe_call(lambda: item.GetName())
        payload = {
            "v": 1,
            "type": "fusion_state",
            "available": available,
            "reason": None if available else (reason or "No Fusion comp available"),
            "current_page": (safe_call(lambda: resolve.GetCurrentPage())
                             if resolve is not None else None),
            "clip": clip,
            "comp_count": self._fusion_comp_count(item),
            "comp_names": self._fusion_comp_names(item),
        }
        active_entry = None
        target = tool
        if comp is not None:
            missing = object()
            active = safe_call(lambda: getattr(comp, "ActiveTool", None), missing)
            if active is not missing and active is not None:
                active_entry = self._tool_entry(active)
                if target is None:
                    target = active
        payload["active_tool"] = active_entry

        params = []
        center = None
        if target is not None:
            entry = self._tool_entry(target)
            payload["tool"] = entry
            for param in sorted(FUSION_PARAM_MAP.get(entry["type"], {})):
                low, high, default, _step = FUSION_PARAM_MAP[entry["type"]][param]
                value = safe_call(lambda p=param: target.GetInput(p))
                params.append({
                    "id": param,
                    "value": float(value) if isinstance(value, (int, float)) else None,
                    "min": low,
                    "max": high,
                    "default": default,
                })
            center_input = FUSION_XY_MAP.get(entry["type"])
            if center_input:
                center = self._read_center(target, center_input)
        else:
            payload["tool"] = None
        payload["params"] = params
        payload["center"] = center
        emit(payload)

    def _process_fusion_batch(self, cmds):
        """Apply one drained batch of knob/XY commands: coalesce per
        (tool, param), one SetInput each, one fusion_state at the end. Runs
        under self.lock via process_batch. Unmapped/non-numeric targets are
        refused (logged), never set blind."""
        deltas = {}      # (tool_name, param) -> summed ticks*speed
        xy = {}          # tool_name -> [dx, dy]
        resets = []      # (tool_name, param), arrival order
        target_name = None
        for cmd in cmds:
            name = cmd.get("cmd")
            tool_name = str(cmd.get("tool_name") or "").strip()
            if not tool_name:
                continue
            target_name = tool_name
            if name == "fusion_param_delta":
                key = (tool_name, str(cmd.get("param") or ""))
                amount = (cmd.get("ticks") or 0) * (cmd.get("speed") or 1.0)
                deltas[key] = deltas.get(key, 0.0) + amount
            elif name == "fusion_xy_delta":
                vec = xy.setdefault(tool_name, [0.0, 0.0])
                vec[0] += cmd.get("dx") or 0.0
                vec[1] += cmd.get("dy") or 0.0
            elif name == "fusion_param_reset":
                key = (tool_name, str(cmd.get("param") or ""))
                # A reset makes earlier deltas for the same param obsolete.
                deltas.pop(key, None)
                resets.append(key)
        if not deltas and not xy and not resets:
            return

        resolve, _, item, _, comp, reason = self._fusion_objects()
        if comp is None:
            self._emit_fusion_state(resolve, item, None, reason=reason)
            return

        def rule_for(tool, param):
            if tool is None:
                return None
            return FUSION_PARAM_MAP.get(self._tool_entry(tool)["type"], {}).get(param)

        by_name = {}
        for tool in self._fusion_tools(comp) or []:
            by_name[self._tool_entry(tool)["name"]] = tool

        for (tool_name, param), amount in deltas.items():
            tool = by_name.get(tool_name)
            rule = rule_for(tool, param)
            if rule is None:
                log("fusion delta ignored: %s.%s unmapped or tool missing"
                    % (tool_name, param))
                continue
            low, high, _default, step = rule
            current = safe_call(lambda t=tool, p=param: t.GetInput(p))
            if not isinstance(current, (int, float)):
                log("fusion delta refused: %s.%s value %r is not numeric"
                    % (tool_name, param, current))
                continue
            value = clamped(float(current) + amount * step, (low, high))
            try:
                tool.SetInput(param, value)
            except Exception as exc:
                log("SetInput %s.%s failed: %s" % (tool_name, param, exc))

        for tool_name, vec in xy.items():
            tool = by_name.get(tool_name)
            center_input = (FUSION_XY_MAP.get(self._tool_entry(tool)["type"])
                            if tool is not None else None)
            if center_input is None:
                log("fusion xy ignored: %s has no mapped point input" % tool_name)
                continue
            current = self._read_center(tool, center_input)
            if current is None:
                log("fusion xy refused: %s.%s is not a readable point"
                    % (tool_name, center_input))
                continue
            point = [clamped(current[0] + vec[0], CLAMP_FUSION_CENTER),
                     clamped(current[1] + vec[1], CLAMP_FUSION_CENTER)]
            try:
                tool.SetInput(center_input, point)
            except Exception as exc:
                log("SetInput %s.%s failed: %s" % (tool_name, center_input, exc))

        for tool_name, param in resets:
            tool = by_name.get(tool_name)
            if tool is None:
                continue
            rule = rule_for(tool, param)
            center_input = FUSION_XY_MAP.get(self._tool_entry(tool)["type"])
            try:
                if rule is not None:
                    tool.SetInput(param, rule[2])
                elif center_input and param == center_input:
                    tool.SetInput(center_input, list(FUSION_CENTER_DEFAULT))
                else:
                    log("fusion reset ignored: %s.%s unmapped" % (tool_name, param))
            except Exception as exc:
                log("reset SetInput %s.%s failed: %s" % (tool_name, param, exc))

        self._emit_fusion_state(resolve, item, comp,
                                tool=by_name.get(target_name))

    def _fusion_cmd_status(self, cmd):
        """fusion_state on demand (tab appear, poll, after client actions)."""
        resolve, _, item, _, comp, reason = self._fusion_objects()
        tool = None
        tool_name = str(cmd.get("tool_name") or "").strip()
        if tool_name and comp is not None:
            tool = self._fusion_tool_by_name(comp, tool_name)
        self._emit_fusion_state(resolve, item, comp, tool=tool, reason=reason)

    def _fusion_cmd_add_tool(self, cmd):
        """Production tool grid: allowlisted AddTool + best-effort select,
        then a fresh fusion_state targeting the new tool."""
        if not self._require_confirm(cmd):
            return
        tool_id = str(cmd.get("tool_id") or "").strip()
        if tool_id not in FUSION_ADD_TOOL_IDS:
            emit_fusion_result(
                "fusion_add_tool", False, reason="tool_not_allowlisted",
                message="%s is not in the Fusion tool allowlist" % (tool_id or "?"))
            return
        resolve, _, item, _, comp, reason = self._fusion_objects()
        if resolve is None:
            emit_fusion_result("fusion_add_tool", False, reason="no_resolve",
                               message=reason)
            return
        if comp is None:
            emit_fusion_result("fusion_add_tool", False, reason="no_comp",
                               message=reason or "No Fusion comp available")
            return
        if not has_method(comp, "AddTool"):
            emit_fusion_result("fusion_add_tool", False, reason="unsupported",
                               message="AddTool is unavailable on this comp")
            return
        tool = comp.AddTool(tool_id)
        ok = tool is not None
        log("fusion_add_tool: %s ok=%s" % (tool_id, ok))
        if ok and has_method(comp, "SetActiveTool"):
            safe_call(lambda: comp.SetActiveTool(tool))
        emit_fusion_result(
            "fusion_add_tool", ok,
            message="Added %s" % tool_id if ok
                    else "Resolve refused to add %s (id may be wrong on this "
                         "version — please report)" % tool_id,
            reason=None if ok else "resolve_error",
            details={"tool": self._tool_entry(tool) if ok else None})
        self._emit_fusion_state(resolve, item, comp, tool=tool if ok else None)

    def _fusion_cmd_select_tool(self, cmd):
        """Best-effort SetActiveTool so Resolve's UI follows the iPad; the
        iPad never depends on it (params are name-targeted)."""
        tool_name = str(cmd.get("tool_name") or "").strip()
        resolve, _, item, _, comp, reason = self._fusion_objects()
        if resolve is None:
            emit_fusion_result("fusion_select_tool", False, reason="no_resolve",
                               message=reason)
            return
        if comp is None:
            emit_fusion_result("fusion_select_tool", False, reason="no_comp",
                               message=reason or "No Fusion comp available")
            return
        tool = self._fusion_tool_by_name(comp, tool_name)
        if tool is None:
            emit_fusion_result("fusion_select_tool", False, reason="tool_not_found",
                               message="No tool named %r in the comp" % tool_name)
            return
        if has_method(comp, "SetActiveTool"):
            safe_call(lambda: comp.SetActiveTool(tool))
            emit_fusion_result("fusion_select_tool", True,
                               message="Selected %s" % tool_name)
        else:
            emit_fusion_result(
                "fusion_select_tool", False, reason="unsupported",
                message="SetActiveTool is unavailable; iPad-side selection still works")
        self._emit_fusion_state(resolve, item, comp, tool=tool)

    def _fusion_cmd_load_comp(self, cmd):
        resolve, _, item, _, _, reason = self._fusion_objects()
        if resolve is None:
            emit_fusion_result("fusion_load_comp", False, reason="no_resolve",
                               message=reason)
            return
        if item is None:
            emit_fusion_result("fusion_load_comp", False, reason="no_clip",
                               message=reason)
            return
        names = self._fusion_comp_names(item) or []
        try:
            index = int(cmd.get("index"))
        except (TypeError, ValueError):
            index = 0
        if index < 1 or index > len(names):
            emit_fusion_result(
                "fusion_load_comp", False, reason="invalid_index",
                message="No comp at index %s (clip has %d)" % (cmd.get("index"), len(names)))
            return
        if not has_method(item, "LoadFusionCompByName"):
            emit_fusion_result("fusion_load_comp", False, reason="unsupported",
                               message="LoadFusionCompByName is unavailable")
            return
        loaded = item.LoadFusionCompByName(names[index - 1])
        ok = loaded is not None
        log("fusion_load_comp: %r ok=%s" % (names[index - 1], ok))
        emit_fusion_result(
            "fusion_load_comp", ok,
            message="Loaded %r" % names[index - 1] if ok
                    else "Resolve refused to load the comp",
            reason=None if ok else "resolve_error",
            details={"comp_names": names})
        resolve2, _, item2, _, comp2, _ = self._fusion_objects()
        self._emit_fusion_state(resolve2, item2, comp2)

    def _fusion_cmd_delete_comp(self, cmd):
        """The one destructive comp action — requires confirm:true (the iPad
        additionally shows a real confirmation dialog)."""
        if not self._require_confirm(cmd):
            return
        resolve, _, item, _, _, reason = self._fusion_objects()
        if resolve is None:
            emit_fusion_result("fusion_delete_comp", False, reason="no_resolve",
                               message=reason)
            return
        if item is None:
            emit_fusion_result("fusion_delete_comp", False, reason="no_clip",
                               message=reason)
            return
        names = self._fusion_comp_names(item) or []
        try:
            index = int(cmd.get("index"))
        except (TypeError, ValueError):
            index = 0
        if index < 1 or index > len(names):
            emit_fusion_result(
                "fusion_delete_comp", False, reason="invalid_index",
                message="No comp at index %s (clip has %d)" % (cmd.get("index"), len(names)))
            return
        if not has_method(item, "DeleteFusionCompByName"):
            emit_fusion_result("fusion_delete_comp", False, reason="unsupported",
                               message="DeleteFusionCompByName is unavailable")
            return
        ok = bool(item.DeleteFusionCompByName(names[index - 1]))
        log("fusion_delete_comp: %r ok=%s" % (names[index - 1], ok))
        emit_fusion_result(
            "fusion_delete_comp", ok,
            message="Deleted %r" % names[index - 1] if ok
                    else "Resolve refused the delete",
            reason=None if ok else "resolve_error",
            details={"comp_names": self._fusion_comp_names(item)})
        resolve2, _, item2, _, comp2, _ = self._fusion_objects()
        self._emit_fusion_state(resolve2, item2, comp2)

    def _fusion_cmd_list_comp_files(self, cmd):
        """Fresh COMPS_DIR scan (folder is the source of truth, like Looks)."""
        try:
            files = sorted(
                os.path.splitext(entry)[0]
                for entry in os.listdir(COMPS_DIR)
                if entry.lower().endswith(".comp") and not entry.startswith(".")
            )
        except OSError as exc:
            log("could not scan %s: %s" % (COMPS_DIR, exc))
            files = []
        emit({"v": 1, "type": "fusion_comp_files", "files": files})

    def _fusion_cmd_import_comp_file(self, cmd):
        """Import a preset .comp from COMPS_DIR by basename (the MACROS
        chips). Traversal-guarded; the file must already be in the folder."""
        if not self._require_confirm(cmd):
            return
        name = str(cmd.get("name") or "").strip()
        if not name or os.path.basename(name) != name:
            emit_fusion_result("fusion_import_comp_file", False,
                               reason="invalid_path",
                               message="name must be a bare .comp basename")
            return
        path = os.path.join(COMPS_DIR, name + ".comp")
        if not os.path.isfile(path):
            emit_fusion_result("fusion_import_comp_file", False,
                               reason="invalid_path",
                               message="No %s.comp in %s" % (name, COMPS_DIR))
            return
        resolve, _, item, _, _, reason = self._fusion_objects()
        if resolve is None:
            emit_fusion_result("fusion_import_comp_file", False,
                               reason="no_resolve", message=reason)
            return
        if item is None:
            emit_fusion_result("fusion_import_comp_file", False,
                               reason="no_clip", message=reason)
            return
        if not has_method(item, "ImportFusionComp"):
            emit_fusion_result("fusion_import_comp_file", False,
                               reason="unsupported",
                               message="ImportFusionComp is unavailable")
            return
        comp = item.ImportFusionComp(path)
        ok = comp is not None
        log("fusion_import_comp_file: %s ok=%s" % (name, ok))
        emit_fusion_result(
            "fusion_import_comp_file", ok,
            message="Imported %s" % name if ok else "Resolve refused the import",
            reason=None if ok else "resolve_error",
            details={"comp_count": self._fusion_comp_count(item),
                     "comp_names": self._fusion_comp_names(item)})
        resolve2, _, item2, _, comp2, _ = self._fusion_objects()
        self._emit_fusion_state(resolve2, item2, comp2)

    # -- node FX inventory (Phase 19) -----------------------------------------

    def handle_node_tools(self, cmd):
        """Read-only Color-page inventory: per node, its label and the
        tools/ResolveFX inside it via Graph.GetToolsInNode. Introspection
        only — Resolve's API cannot add or modify colour nodes, so this
        answers 'what FX are on this clip', never changes it. Runs on the
        reader thread (instant, works while grading)."""
        with self.lock:
            _, item, reason = self.session.current_context()
            if item is None:
                emit({"v": 1, "type": "node_tools", "available": False,
                      "reason": reason})
                return
            graph = None
            if has_method(item, "GetNodeGraph"):
                graph = safe_call(lambda: item.GetNodeGraph())
            if graph is None:
                emit({"v": 1, "type": "node_tools", "available": False,
                      "reason": "Clip has no readable node graph"})
                return
            if not has_method(graph, "GetToolsInNode"):
                emit({"v": 1, "type": "node_tools", "available": False,
                      "reason": "GetToolsInNode is unavailable on this Resolve"})
                return
            count = self.fresh_node_count(item)
            nodes = []
            for index in range(1, count + 1):
                tools = safe_call(lambda i=index: graph.GetToolsInNode(i))
                if isinstance(tools, dict):
                    tools = [tools[key] for key in sorted(tools)]
                if not isinstance(tools, (list, tuple)):
                    tools = []
                label = None
                if has_method(graph, "GetNodeLabel"):
                    label = safe_call(lambda i=index: graph.GetNodeLabel(i))
                nodes.append({
                    "index": index,
                    "label": str(label) if label else "",
                    "tools": [str(tool) for tool in tools],
                })
            emit({"v": 1, "type": "node_tools", "available": True,
                  "node": self.active_node, "node_count": count,
                  "nodes": nodes})
            log("node_tools: %d node(s) inventoried" % count)

    # -- bypass (hold-to-compare) -------------------------------------------

    def handle_bypass(self, enabled):
        """Called directly from the reader thread; must feel instant."""
        with self.lock:
            if enabled and self.bypassed_node is None:
                return  # idempotent: nothing to re-enable
            _, item, reason = self.session.current_context()
            if item is None:
                log("bypass ignored: %s" % reason)
                return
            # Re-enable targets whichever node was bypassed, even if the
            # stepper has moved since.
            node = self.bypassed_node if enabled else self.active_node
            if self._set_node_enabled(item, node, enabled):
                self.bypassed_node = None if enabled else node
                log("node %d %s" % (node, "enabled" if enabled else "bypassed"))

    def _set_node_enabled(self, item, node, enabled):
        try:
            # Re-fetch the graph every call — cheap, and avoids stale handles.
            graph = item.GetNodeGraph()
            if graph is None:
                log("bypass failed: clip has no node graph")
                return False
            return bool(graph.SetNodeEnabled(node, enabled))
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
        # Fusion knob/XY ticks (Phase 17) share the 30Hz batch cadence but
        # have their own coalescing + apply path; they must never fall into
        # the colour no-context handling below.
        fusion_cmds = [c for c in remaining if c.get("mode") == "fusion"]
        if fusion_cmds:
            remaining = [c for c in remaining if c.get("mode") != "fusion"]
            self._process_fusion_batch(fusion_cmds)
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
                    elif cmd.get("cmd") in ("reset_grade", "set_lut", "apply_drx"):
                        # Smoke-test actions always get an explicit answer.
                        emit_color_result(cmd.get("cmd"), False,
                                          reason="no_color_context", message=reason)
            self.announce(False, reason=reason, force=wants_status)
            return

        changed = False
        node_switched = False
        state = None

        for cmd in mutating:
            name = cmd.get("cmd")
            # Freshness rule: re-read the node tree for EVERY command and
            # re-point the working state — the user may add/delete nodes in
            # Resolve at any moment.
            node_count = self.fresh_node_count(item)
            state = self.state_for(item)
            if name == "set_node":
                try:
                    requested = int(cmd.get("index") or 1)
                except (TypeError, ValueError):
                    requested = 1
                self.active_node = min(max(requested, 1), node_count)
                # Later commands in this batch land on the new node.
                state = self.state_for(item)
                node_switched = True
            elif name == "color_delta":
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
            elif name == "reset_grade":
                if self.reset_grade(item, cmd):
                    # The whole grade is gone; earlier deltas are obsolete.
                    state = self.state_for(item)
                    changed = False
            elif name == "set_lut":
                self.set_lut(item, cmd)
            elif name == "apply_drx":
                if self.apply_drx_command(item, cmd):
                    state = self.state_for(item)
                    changed = False
            else:
                log("unknown colour command: %r" % name)

        if changed and state is not None:
            # Grading while bypassed would be invisible and confusing — make
            # sure the bypassed node is back on before the next apply.
            if self.bypassed_node is not None and self._set_node_enabled(item, self.bypassed_node, True):
                log("node %d re-enabled before apply" % self.bypassed_node)
                self.bypassed_node = None
            if not self.apply_cdl(item, state):
                self.announce(False, force=True,
                              reason="Resolve rejected SetCDL on node %d" % self.active_node)
                return

        self.announce(True, item=item,
                      force=changed or wants_status or node_switched)

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

    def _apply_drx_file(self, item, path):
        """Shared DRX-application core (looks presets AND the smoke-test
        apply_drx). Returns (ok, reason). On success the clip's shadow trims
        are purged and a forced color_state is announced — the DRX can
        rewrite the whole node tree."""
        # Same rule as wheel input: grading while bypassed is invisible.
        if self.bypassed_node is not None and self._set_node_enabled(item, self.bypassed_node, True):
            self.bypassed_node = None

        try:
            graph = item.GetNodeGraph()
            if graph is None:
                return False, "Clip has no node graph"
            ok = bool(graph.ApplyGradeFromDRX(path, 0))  # 0 = no keyframes
            # WORKAROUND for a Resolve macOS API bug: a graph handle obtained
            # BEFORE ApplyGradeFromDRX can crash Resolve if used again
            # afterwards. Re-fetch immediately and drop both handles so
            # nothing stale can leak into later calls.
            graph = item.GetNodeGraph()
            del graph
        except Exception as exc:
            log("ApplyGradeFromDRX failed: %s" % exc)
            return False, "Resolve error applying DRX: %s" % exc

        if not ok:
            return False, "Resolve rejected the DRX"

        self._purge_clip_state(item)
        return True, None

    def _purge_clip_state(self, item):
        """Drop the shadow trims for ALL of a clip's nodes (without calling
        SetCDL) and tell the phone so its readouts zero out."""
        uid = item.GetUniqueId()
        self.states = {
            key: value for key, value in self.states.items() if key[0] != uid
        }
        self.announce(True, item=item, force=True)

    def apply_preset(self, item, name):
        """Apply a .drx look to the current clip. Returns True when applied
        (so the caller can refresh its shadow-state handle)."""
        path = os.path.join(LOOKS_DIR, name + ".drx")
        if not os.path.isfile(path):
            emit({"v": 1, "cmd": "preset_applied", "name": name, "ok": False,
                  "reason": "Preset file not found — refresh the list"})
            return False

        ok, reason = self._apply_drx_file(item, path)
        if not ok:
            emit({"v": 1, "cmd": "preset_applied", "name": name, "ok": False,
                  "reason": reason})
            return False

        emit({"v": 1, "cmd": "preset_applied", "name": name, "ok": True})
        log("applied preset %r" % name)
        return True

    # -- colour action smoke tests (Phase 14) --------------------------------

    def reset_grade(self, item, cmd):
        """Resolve's real ResetAllGrades on the current clip. DESTRUCTIVE:
        refuses without confirm:true. Returns True when the grade was reset
        (caller re-points its shadow-state handle)."""
        if cmd.get("confirm") is not True:
            emit_command_rejected("reset_grade", "confirmation_required",
                                  "Reset Grade requires confirm:true")
            return False
        try:
            graph = item.GetNodeGraph()
            if graph is None:
                emit_color_result("reset_grade", False, reason="no_node_graph",
                                  message="Clip has no node graph")
                return False
            reset = getattr(graph, "ResetAllGrades", None)
            if not callable(reset):
                emit_color_result("reset_grade", False, reason="api_unavailable",
                                  message="ResetAllGrades is not exposed by this Resolve")
                return False
            ok = bool(reset())
        except Exception as exc:
            log("ResetAllGrades failed: %s" % exc)
            emit_color_result("reset_grade", False, reason="resolve_error",
                              message="Resolve error: %s" % exc)
            return False

        if not ok:
            emit_color_result("reset_grade", False, reason="resolve_rejected",
                              message="Resolve rejected ResetAllGrades")
            return False

        # The grade (and our trims on it) are gone.
        self._purge_clip_state(item)
        emit_color_result("reset_grade", True, message="All grades reset on current clip")
        log("reset_grade: all grades reset")
        return True

    def set_lut(self, item, cmd):
        """Apply a LUT to a node. Requires an explicit lut_path — never picks
        a default. node_index defaults to the stepper-selected active node."""
        lut_path = (cmd.get("lut_path") or "").strip()
        if not lut_path:
            emit_color_result("set_lut", False, reason="missing_path",
                              message="set_lut requires a lut_path")
            return
        # Validate when we can: absolute paths must exist. Relative names may
        # refer to Resolve's own LUT directory, so those are attempted as-is.
        if os.path.isabs(lut_path) and not os.path.isfile(lut_path):
            emit_color_result("set_lut", False, reason="invalid_path",
                              message="No file at %s" % lut_path,
                              details={"lut_path": lut_path})
            return
        node = cmd.get("node_index") or cmd.get("index") or self.active_node
        try:
            node = max(1, int(node))
        except (TypeError, ValueError):
            node = self.active_node
        try:
            graph = item.GetNodeGraph()
            if graph is None:
                emit_color_result("set_lut", False, reason="no_node_graph",
                                  message="Clip has no node graph")
                return
            setter = getattr(graph, "SetLUT", None)
            if not callable(setter):
                emit_color_result("set_lut", False, reason="api_unavailable",
                                  message="SetLUT is not exposed by this Resolve")
                return
            ok = bool(setter(node, lut_path))
        except Exception as exc:
            log("SetLUT failed: %s" % exc)
            emit_color_result("set_lut", False, reason="resolve_error",
                              message="Resolve error: %s" % exc,
                              details={"node_index": node, "lut_path": lut_path})
            return
        emit_color_result("set_lut", ok,
                          message="LUT applied to node %d" % node if ok
                                  else "Resolve rejected the LUT",
                          reason=None if ok else "resolve_rejected",
                          details={"node_index": node, "lut_path": lut_path})
        log("set_lut node=%d ok=%s" % (node, ok))

    def apply_drx_command(self, item, cmd):
        """Smoke-test DRX apply from an explicit path (the Looks strip stays
        the everyday path). Never picks a default file."""
        drx_path = (cmd.get("drx_path") or "").strip()
        if not drx_path:
            emit_color_result("apply_drx", False, reason="missing_path",
                              message="apply_drx requires a drx_path")
            return False
        if not os.path.isfile(drx_path):
            emit_color_result("apply_drx", False, reason="invalid_path",
                              message="No file at %s" % drx_path,
                              details={"drx_path": drx_path})
            return False
        ok, reason = self._apply_drx_file(item, drx_path)
        emit_color_result("apply_drx", ok,
                          message="DRX applied" if ok else reason,
                          reason=None if ok else "resolve_rejected",
                          details={"drx_path": drx_path})
        log("apply_drx %s ok=%s" % (drx_path, ok))
        return ok

    def grab_still(self, timeline):
        ok = False
        try:
            # Resolve's Python bridge returns None (not AttributeError) for
            # methods the running version doesn't have, so check callability.
            # Current API: Timeline.GrabStill(); fall back to the older
            # GrabStillFromCurrentVideoClip() name just in case.
            grab = getattr(timeline, "GrabStill", None)
            if not callable(grab):
                grab = getattr(timeline, "GrabStillFromCurrentVideoClip", None)
            if not callable(grab):
                log("grab_still: this Resolve version exposes no still-grab API")
            else:
                ok = grab() is not None
        except Exception as exc:
            log("grab_still failed: %s" % exc)
            ok = False
        emit({"v": 1, "cmd": "still_grabbed", "ok": ok})

    def apply_cdl(self, item, state):
        try:
            return bool(item.SetCDL(compose_cdl(state, node_index=str(self.active_node))))
        except Exception as exc:
            log("SetCDL failed: %s" % exc)
            self.session.resolve = None
            return False

    def announce(self, available, item=None, reason=None, force=False):
        """Emit color_state when availability flips, or when forced. Node
        count and the working state are re-derived fresh at emission time —
        nothing cached — so the phone always sees the live node tree."""
        if not force and available == self.last_available:
            return
        self.last_available = available
        if available:
            node_count = self.fresh_node_count(item)
            state = self.state_for(item)
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
                "node": self.active_node,
                "node_count": node_count,
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
            elif cmd.get("cmd") == "capability_probe":
                # System introspection: answer immediately, off the colour
                # batch, so it works even with no project/clip open.
                engine.handle_capability_probe(cmd)
            elif cmd.get("cmd") == "node_tools":
                # Read-only node-FX inventory (Phase 19): instant, never
                # queued behind grading batches.
                engine.handle_node_tools(cmd)
            elif cmd.get("cmd") == "fusion_probe":
                # Fusion introspection (Phase 15): same contract as the
                # capability probe — immediate, non-mutating.
                engine.handle_fusion_probe(cmd)
            elif cmd.get("cmd") == "open_fusion_page":
                # The one mutating Fusion action this phase; instant, off
                # the colour batch.
                engine.handle_open_fusion_page(cmd)
            elif cmd.get("mode") == "fusion" and cmd.get("cmd") in FUSION_BATCHED_CMDS:
                # Live knob/XY ticks (Phase 17): rate-limited + coalesced
                # on the batch worker, like the colour deltas.
                commands.put(cmd)
            elif cmd.get("mode") == "fusion":
                # Fusion actions (Phases 16/17): immediate, guarded
                # (confirm:true) and allowlisted inside the dispatcher.
                engine.handle_fusion_action(cmd)
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
    try:
        os.makedirs(COMPS_DIR, exist_ok=True)
        log("comps folder: %s" % COMPS_DIR)
    except OSError as exc:
        log("could not create comps folder %s: %s" % (COMPS_DIR, exc))
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

    # Never exit with a node silently bypassed.
    if engine.bypassed_node is not None:
        engine.handle_bypass(True)
    log("stdin closed, exiting")


if __name__ == "__main__":
    main()
