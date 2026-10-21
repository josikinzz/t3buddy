#!/usr/bin/env python3
"""Deterministic stills of the pet page, captured with headless Google Chrome. Standard library only.

    python3 -I scripts/pet_stills.py capture OUTDIR [--pet KIND] [SCENE ...]
    python3 -I scripts/pet_stills.py compare BEFORE AFTER
    python3 -I scripts/pet_stills.py film OUTDIR SCENE [--pet KIND] [--fps N] [--from SECONDS]

`capture` serves Resources/ on loopback, opens Pet/index.html?still=SCENE&pet=KIND (still.js plays
the scene on a synthetic clock) and saves OUTDIR/KIND-SCENE.png once the page's title says it is
done, with OUTDIR/KIND-SCENE.json beside it: hit regions, anchors, orbit geometry, orbs and mood,
which the pixels don't show. Rendering is software (SwiftShader), so the same tree gives the same
pixels. `compare` prints, per same-named file, identical bytes or how many pixels differ (or whether
the state matches), and exits 1 on any difference. `film` saves OUTDIR/KIND-SCENE-0000.png and on,
N frames a second of scene time (default 6) from SECONDS (default 0) to the scene's end, for
ffmpeg.
"""

import base64
import functools
import http.server
import json
import os
import struct
import subprocess
import sys
import tempfile
import threading
import time
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CHROME = os.environ.get("CHROME", "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")
SCENES = ["idle", "busy", "swallow", "fretful", "eggs", "cry", "weep", "blink", "sleep", "dance", "shake", "spawn", "power",
          "dozy", "focused", "satisfied", "look", "bright"]
VIEW = {"width": 1200, "height": 1000}
SCENE_TIMEOUT_S = 180
# What the pixels don't show, saved beside each still: hit regions, anchors, the ball, orbit geometry, mood
# and the scene's own evidence, if it has any.
STATE_JS = """JSON.stringify((() => { const t = window.t3boii; return { hitRegions: t.hitRegions(), forehead: t.foreheadAnchor(),
  geometry: t.orbit.geometry, orbs: t.orbit.state(), mood: t.mood, evidence: window.__stillEvidence }; })())"""


class DevTools:
    """Chrome's DevTools protocol over --remote-debugging-pipe (fd 3 in, fd 4 out, NUL-framed JSON)."""

    def __init__(self, profile):
        to_chrome_r, self.to_chrome = os.pipe()
        self.from_chrome, from_chrome_w = os.pipe()

        def wire():
            os.dup2(to_chrome_r, 3)
            os.dup2(from_chrome_w, 4)

        self.process = subprocess.Popen(
            [CHROME, "--headless=new", "--remote-debugging-pipe", "--use-angle=swiftshader", "--enable-unsafe-swiftshader",
             f"--user-data-dir={profile}", "--no-first-run", "--no-default-browser-check", "--mute-audio", "--hide-scrollbars",
             "--force-device-scale-factor=1", f"--window-size={VIEW['width']},{VIEW['height']}", "about:blank"],
            preexec_fn=wire, pass_fds=(3, 4, to_chrome_r, from_chrome_w), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        os.close(to_chrome_r)
        os.close(from_chrome_w)
        self.buffer, self.next_id, self.log = b"", 0, []

    def _read(self):
        while b"\0" not in self.buffer:
            chunk = os.read(self.from_chrome, 1 << 16)
            if not chunk:
                raise RuntimeError("Chrome closed the DevTools pipe")
            self.buffer += chunk
        message, self.buffer = self.buffer.split(b"\0", 1)
        return json.loads(message)

    def call(self, method, params=None, session=None):
        self.next_id += 1
        message = {"id": self.next_id, "method": method, "params": params or {}}
        if session:
            message["sessionId"] = session
        os.write(self.to_chrome, json.dumps(message).encode() + b"\0")
        while True:
            reply = self._read()
            if reply.get("method") == "Runtime.exceptionThrown":
                self.log.append(reply["params"]["exceptionDetails"].get("exception", {}).get("description", "exception"))
            elif reply.get("method") == "Runtime.consoleAPICalled" and reply["params"]["type"] == "error":
                self.log.append(" ".join(str(a.get("value", a.get("description", ""))) for a in reply["params"]["args"]))
            if reply.get("id") == self.next_id:
                if "error" in reply:
                    raise RuntimeError(f"{method}: {reply['error']}")
                return reply["result"]

    def close(self):
        try:
            self.call("Browser.close")
        except Exception:
            pass
        try:
            self.process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            self.process.kill()


def serve(directory):
    handler = functools.partial(type("Quiet", (http.server.SimpleHTTPRequestHandler,), {"log_message": lambda *a: None}), directory=directory)
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server


def open_scene(chrome, server, scene, pet, extra=""):
    """A new tab playing `scene`; returns its target, session and final title."""
    target = chrome.call("Target.createTarget", {"url": "about:blank"})["targetId"]
    session = chrome.call("Target.attachToTarget", {"targetId": target, "flatten": True})["sessionId"]
    chrome.call("Runtime.enable", session=session)
    chrome.call("Emulation.setDeviceMetricsOverride", {**VIEW, "deviceScaleFactor": 1, "mobile": False}, session=session)
    chrome.log = []
    url = f"http://127.0.0.1:{server.server_port}/Pet/index.html?still={scene}&pet={pet}{extra}"
    chrome.call("Page.navigate", {"url": url}, session=session)
    deadline, title = time.time() + SCENE_TIMEOUT_S, ""
    while time.time() < deadline:
        title = chrome.call("Runtime.evaluate", {"expression": "document.title", "returnByValue": True}, session=session)["result"].get("value", "")
        if title.startswith(f"still:{scene}:"):
            break
        time.sleep(0.2)
    return target, session, title


def film(out, pet, scene, fps, start):
    if not os.access(CHROME, os.X_OK):
        sys.exit(f"pet_stills: no Chrome at {CHROME} (set CHROME)")
    os.makedirs(out, exist_ok=True)
    server = serve(os.path.join(ROOT, "Resources"))
    with tempfile.TemporaryDirectory() as profile:
        chrome = DevTools(profile)
        try:
            _, session, title = open_scene(chrome, server, scene, pet, f"&film={fps}&from={start}")
            if title != f"still:{scene}:done":
                print(f"pet_stills: {pet} {scene} did not start filming (title {title!r}) {' | '.join(chrome.log)}", file=sys.stderr)
                return 1
            count = 0
            while True:
                shot = chrome.call("Page.captureScreenshot", {"format": "png"}, session=session)
                open(os.path.join(out, f"{pet}-{scene}-{count:04d}.png"), "wb").write(base64.b64decode(shot["data"]))
                count += 1
                more = chrome.call("Runtime.evaluate", {"expression": "window.__stillNext()", "returnByValue": True}, session=session)["result"].get("value")
                if not more:
                    break
            print(f"{out}: {count} frames")
        finally:
            chrome.close()
            server.shutdown()
    return 0


def capture(out, pet, scenes):
    if not os.access(CHROME, os.X_OK):
        sys.exit(f"pet_stills: no Chrome at {CHROME} (set CHROME)")
    os.makedirs(out, exist_ok=True)
    server = serve(os.path.join(ROOT, "Resources"))
    failed = False
    with tempfile.TemporaryDirectory() as profile:
        chrome = DevTools(profile)
        try:
            for scene in scenes:
                target, session, title = open_scene(chrome, server, scene, pet)
                png = os.path.join(out, f"{pet}-{scene}.png")
                if title == f"still:{scene}:done":
                    shot = chrome.call("Page.captureScreenshot", {"format": "png"}, session=session)
                    open(png, "wb").write(base64.b64decode(shot["data"]))
                    state = json.loads(chrome.call("Runtime.evaluate", {"expression": STATE_JS, "returnByValue": True}, session=session)["result"].get("value"))
                    open(png[:-4] + ".json", "w").write(json.dumps(state, indent=1, sort_keys=True) + "\n")
                    print(png)
                    if (state.get("evidence") or {}).get("ok") is False:
                        failed = True
                        print(f"pet_stills: {pet} {scene}: its evidence fails: {json.dumps(state['evidence'])}", file=sys.stderr)
                else:
                    failed = True
                    print(f"pet_stills: {pet} {scene} did not finish (title {title!r}) {' | '.join(chrome.log)}", file=sys.stderr)
                chrome.call("Target.closeTarget", {"targetId": target})
        finally:
            chrome.close()
            server.shutdown()
    return 1 if failed else 0


def decode(path):
    data = open(path, "rb").read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"{path} is not a PNG")
    offset, idat, header = 8, b"", None
    while offset < len(data):
        length, kind = struct.unpack_from(">I4s", data, offset)
        body = data[offset + 8: offset + 8 + length]
        if kind == b"IHDR":
            header = struct.unpack(">IIBBBBB", body)
        elif kind == b"IDAT":
            idat += body
        offset += 12 + length
    width, height, depth, color, _, _, interlace = header
    channels = {2: 3, 6: 4}.get(color)
    if depth != 8 or channels is None or interlace:
        raise ValueError(f"{path}: only 8-bit RGB or RGBA, non-interlaced PNGs")
    raw, stride = zlib.decompress(idat), width * channels
    rows, previous = [], bytearray(stride)
    for y in range(height):
        kind, line = raw[y * (stride + 1)], bytearray(raw[y * (stride + 1) + 1: (y + 1) * (stride + 1)])
        for x in range(stride):
            a = line[x - channels] if x >= channels else 0
            b = previous[x]
            c = previous[x - channels] if x >= channels else 0
            if kind == 1:
                line[x] = (line[x] + a) & 255
            elif kind == 2:
                line[x] = (line[x] + b) & 255
            elif kind == 3:
                line[x] = (line[x] + (a + b) // 2) & 255
            elif kind == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                line[x] = (line[x] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        rows.append(bytes(line))
        previous = line
    return width, height, channels, rows


def difference(before, after):
    if open(before, "rb").read() == open(after, "rb").read():
        return 0, "identical bytes"
    wa, ha, ca, ra = decode(before)
    wb, hb, cb, rb = decode(after)
    if (wa, ha, ca) != (wb, hb, cb):
        return -1, f"sizes differ: {wa}x{ha}x{ca} vs {wb}x{hb}x{cb}"
    changed, worst = 0, 0
    for row_a, row_b in zip(ra, rb):
        if row_a == row_b:
            continue
        for x in range(0, len(row_a), ca):
            delta = max(abs(row_a[x + k] - row_b[x + k]) for k in range(ca))
            if delta:
                changed, worst = changed + 1, max(worst, delta)
    return changed, f"{changed} of {wa * ha} pixels differ, by at most {worst}/255" if changed else "identical pixels"


def compare(before, after):
    names = sorted(n for n in set(os.listdir(before)) | set(os.listdir(after)) if n.endswith((".png", ".json")))
    scenes = sorted({n.rsplit(".", 1)[0] for n in names})
    if not scenes:
        print("no stills to compare: an empty set proves nothing")
        return 1
    failed = False
    for scene in scenes:
        for name in (scene + ".png", scene + ".json"):
            a, b = os.path.join(before, name), os.path.join(after, name)
            missing = [side for side, path in (("before", a), ("after", b)) if not os.path.exists(path)]
            if missing:
                print(f"{name}: missing from {' and '.join(missing)}")
                failed = True
                continue
            if name.endswith(".json"):
                same = json.load(open(a)) == json.load(open(b))
                print(f"{name}: {'same state' if same else 'state differs'}")
            else:
                same = open(a, "rb").read() == open(b, "rb").read()
                print(f"{name}: {'identical bytes' if same else 'bytes differ (' + difference(a, b)[1] + ')'}")
            failed |= not same
    return 1 if failed else 0


def main(argv):
    if len(argv) >= 3 and argv[0] == "compare":
        return compare(argv[1], argv[2])
    if len(argv) >= 3 and argv[0] == "film":
        out, scene, rest = argv[1], argv[2], argv[3:]
        options = dict(zip(rest[::2], rest[1::2]))
        return film(out, options.get("--pet", "t3boii"), scene, float(options.get("--fps", 6)), float(options.get("--from", 0)))
    if len(argv) >= 2 and argv[0] == "capture":
        out, rest, pet = argv[1], argv[2:], "t3boii"
        if rest[:1] == ["--pet"]:
            pet, rest = rest[1], rest[2:]
        return capture(out, pet, rest or SCENES)
    print(__doc__.split("\n\n")[1], file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
