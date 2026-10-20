#!/usr/bin/env python3
"""Drills the t3boii-feed helper through a T3 restart and a token change, against a fake T3.

Nothing here touches the real T3: the helper gets a fake T3 home (a stub `t3` CLI and a
server-runtime.json pointing at the fake server) and its own token file, both in a temp folder.

    scripts/t3_restart_drill.py [path/to/t3boii-feed]

Passes when a thread that really ends is still swallowed, and when no restart (a new pid in
server-runtime.json, a dropped MCP session, or a restart whose first poll misses the feed's
deadline) and no token change emits a lifecycle event, while the threads the restart cancelled
leave the state and a new one joins it.
"""
import base64, json, os, queue, socket, subprocess, sys, tempfile, threading, time
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HELPER = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, ".build-20261013/debug/t3boii-feed")
LIFECYCLE = {"started", "finished", "vanished", "failed"}


def iso(t=None):
    return datetime.fromtimestamp(t or time.time(), timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"


def t3_token(sid):
    head = base64.urlsafe_b64encode(json.dumps({"v": 1, "kind": "session", "sid": sid}).encode()).decode().rstrip("=")
    return head + ".drill-signature"


class FakeT3:
    """Projects and threads, one MCP session generation per server start, tokens it accepts."""

    def __init__(self, home):
        self.home = home
        self.lock = threading.Lock()
        self.projects = [
            {"id": "p-demo", "title": "demo-app", "workspaceRoot": "/Users/tester/demo-app"},
            {"id": "p-docs", "title": "docs-site", "workspaceRoot": "/Users/tester/docs-site"},
        ]
        self.threads = {}
        self.sessions = set()
        self.tokens = set()
        self.minted = 0
        self.slow_reads = 0
        self.pid = 41000
        self.server = None
        with socket.socket() as probe:
            probe.bind(("127.0.0.1", 0))
            self.port = probe.getsockname()[1]

    def thread(self, tid, project, status, items=5):
        with self.lock:
            self.threads[tid] = {"threadId": tid, "projectId": project, "title": tid, "status": status,
                                 "providerInstanceId": "codex", "itemCount": items, "updatedAt": iso()}

    def set_status(self, tid, status):
        with self.lock:
            self.threads[tid].update(status=status, updatedAt=iso())

    def start(self):
        self.pid += 1
        self.sessions = set()
        with open(os.path.join(self.home, "userdata/server-runtime.json"), "w") as f:
            json.dump({"version": 1, "pid": self.pid, "port": self.port, "origin": f"http://127.0.0.1:{self.port}", "startedAt": iso()}, f)
        fake = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def reply(self, status, body, headers=None):
                data = json.dumps(body).encode() if body is not None else b""
                self.send_response(status)
                self.send_header("Content-Type", "application/json")
                for key, value in (headers or {}).items():
                    self.send_header(key, value)
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)

            def do_POST(self):
                raw = self.rfile.read(int(self.headers.get("Content-Length", 0)))
                if self.path == "/oauth/mcp/register":
                    return self.reply(200, {"client_id": "drill-client"})
                if self.path == "/oauth/mcp/decision":
                    auth = json.loads(raw)["authorization"]
                    return self.reply(200, {"redirectTo": f"{auth['redirect_uri']}?code=drill-code&state={auth['state']}"})
                if self.path == "/oauth/mcp/token":
                    assert parse_qs(raw.decode())["code"] == ["drill-code"]
                    with fake.lock:
                        fake.minted += 1
                        token = t3_token(f"drill-sid-{fake.minted}")
                        fake.tokens.add(token)
                    return self.reply(200, {"access_token": token, "token_type": "Bearer", "expires_in": 3600})
                if self.path != "/mcp":
                    return self.reply(404, None)
                if self.headers.get("Authorization", "")[7:] not in fake.tokens:
                    return self.reply(401, None)
                message = json.loads(raw)
                sid = self.headers.get("Mcp-Session-Id")
                if message.get("method") == "initialize":
                    sid = f"s{fake.pid}-{len(fake.sessions)}"
                    fake.sessions.add(sid)
                    return self.reply(200, {"jsonrpc": "2.0", "id": message["id"], "result": {"protocolVersion": "2025-06-18", "capabilities": {}}}, {"Mcp-Session-Id": sid})
                if sid not in fake.sessions:
                    return self.reply(404, None)
                if "id" not in message:
                    return self.reply(202, None)
                payload = fake.tool(message["params"]["name"], message["params"].get("arguments", {}))
                self.reply(200, {"jsonrpc": "2.0", "id": message["id"], "result": {"content": [{"type": "text", "text": json.dumps(payload)}]}})

        self.server = ThreadingHTTPServer(("127.0.0.1", self.port), Handler)
        threading.Thread(target=self.server.serve_forever, daemon=True).start()

    def stop(self):
        self.server.shutdown()
        self.server.server_close()

    def drop_sessions(self):
        self.sessions = set()

    def slow_next_reads(self, count):
        with self.lock:
            self.slow_reads = count

    def revoke_tokens(self):
        with self.lock:
            self.tokens = set()

    def tool(self, name, args):
        if name == "t3_thread_read":
            with self.lock:
                slow = self.slow_reads > 0
                self.slow_reads -= slow
            if slow:
                # Under the helper's 6 s request timeout, but two outlast its 8 s source deadline.
                time.sleep(4.5)
        with self.lock:
            if name == "t3_project_list":
                return {"projects": self.projects, "nextCursor": None}
            if name == "t3_thread_list":
                statuses = set(args.get("statuses") or [])
                rows = [t for t in self.threads.values() if t["projectId"] == args.get("projectId") and (not statuses or t["status"] in statuses)]
                rows.sort(key=lambda t: t["updatedAt"], reverse=True)
                return {"threads": rows[: args.get("limit", 100)], "nextCursor": None}
            if name == "t3_thread_read":
                t = self.threads[args["threadId"]]
                return {"thread": {"threadId": t["threadId"], "status": t["status"], "pendingRequestCount": 0, "itemCount": t["itemCount"]},
                        "items": [], "nextPosition": None, "hasMore": False}
            if name == "orchestrator_capabilities":
                return {"providers": [{"providerInstanceId": "codex", "driverKind": "codex"}]}
            if name == "t3_environment_read":
                return {"environmentId": "env-drill"}
            return {"requestIds": [], "items": [], "tasks": []}


def main():
    home = tempfile.mkdtemp(prefix="t3boii-drill-")
    os.makedirs(os.path.join(home, "userdata"))
    cli = os.path.join(home, "runtime/versions/1/t3")
    os.makedirs(os.path.dirname(cli))
    with open(cli, "w") as f:
        f.write('#!/bin/sh\ncase "$*" in *pairing*) echo \'{"credential":"drill-pairing"}\';; esac\nexit 0\n')
    os.chmod(cli, 0o755)

    fake = FakeT3(home)
    fake.thread("thread-ends", "p-demo", "running")
    fake.thread("thread-cancelled-by-restart", "p-demo", "running")
    fake.thread("thread-cancelled-by-drop", "p-docs", "waiting")
    fake.thread("thread-cancelled-by-token", "p-docs", "running")
    fake.thread("thread-cancelled-by-slow-restart", "p-demo", "running")
    fake.thread("thread-old", "p-demo", "completed")
    fake.start()

    helper = subprocess.Popen([HELPER, "--tap", "--t3-home", home, "--token-file", os.path.join(home, "token.json")],
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, bufsize=1)
    lines, logs = queue.Queue(), []
    threading.Thread(target=lambda: [lines.put(l) for l in helper.stdout], daemon=True).start()
    threading.Thread(target=lambda: [logs.append(l.rstrip()) for l in helper.stderr], daemon=True).start()
    events, failures = [], []

    def take(seconds):
        until = time.time() + seconds
        while time.time() < until:
            try:
                line = lines.get(timeout=0.2)
            except queue.Empty:
                continue
            item = json.loads(line)
            if "kind" in item and (item.get("id", "t3:").startswith("t3:")):
                events.append((time.time(), item))

    def lifecycle(since):
        return [e for at, e in events if at >= since and e["kind"] in LIFECYCLE]

    def check(ok, what):
        print(("PASS " if ok else "FAIL ") + what)
        if not ok:
            failures.append(what)

    try:
        take(8)
        start = time.time()
        fake.set_status("thread-ends", "completed")
        take(8)
        check([e["id"] for e in lifecycle(start) if e["kind"] == "finished"] == ["t3:thread-ends"], "a thread that ends is swallowed (finished)")

        start = time.time()
        fake.stop()
        take(6)
        fake.set_status("thread-cancelled-by-restart", "cancelled")
        fake.thread("thread-new-after-restart", "p-demo", "running")
        fake.start()
        take(12)
        check(lifecycle(start) == [], f"a restart with a new pid emits no lifecycle events: {lifecycle(start)}")
        check(any("T3 restarted; orbit resynced" in l for l in logs), "the helper logged the restart resync")

        start = time.time()
        fake.drop_sessions()
        fake.set_status("thread-cancelled-by-drop", "cancelled")
        take(10)
        check(lifecycle(start) == [], f"a dropped MCP session emits no lifecycle events: {lifecycle(start)}")

        start = time.time()
        fake.revoke_tokens()
        fake.set_status("thread-cancelled-by-token", "interrupted")
        take(14)
        check(lifecycle(start) == [], f"a token change emits no lifecycle events: {lifecycle(start)}")
        check(fake.minted >= 2 and any("token changed; orbit resynced" in l for l in logs), "the helper minted a new token and resynced")

        start = time.time()
        fake.stop()
        take(6)
        fake.set_status("thread-cancelled-by-slow-restart", "cancelled")
        fake.slow_next_reads(2)
        fake.start()
        take(32)
        check(fake.slow_reads == 0, "the first poll after the restart read slowly")
        check(lifecycle(start) == [], f"a restart whose first poll misses its deadline emits no lifecycle events: {lifecycle(start)}")

        start = time.time()
        fake.set_status("thread-new-after-restart", "completed")
        take(8)
        check([e["id"] for e in lifecycle(start)] == ["t3:thread-new-after-restart"], f"after the resyncs a real ending is swallowed again: {lifecycle(start)}")
        swallowed = {e["id"] for _, e in events if e["kind"] == "finished"}
        check(not swallowed & {"t3:thread-cancelled-by-restart", "t3:thread-cancelled-by-drop", "t3:thread-cancelled-by-token", "t3:thread-cancelled-by-slow-restart"},
              "no thread a restart or token change cancelled is ever swallowed")
    finally:
        helper.terminate()
        fake.stop()
    if failures:
        print("\n".join(["", "helper log:"] + logs[-30:]))
        sys.exit(1)


if __name__ == "__main__":
    main()
