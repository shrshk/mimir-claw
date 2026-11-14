"""mimir-ask against fake mimir-tv and OpenClaw servers on loopback: python3 -m unittest ask/test_mimir_ask.py"""

import json
import os
import tempfile
import threading
import unittest
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import mimir_ask


class Fake(BaseHTTPRequestHandler):
    """mimir-tv's /mcp and OpenClaw's /v1/chat/completions, recording what they were asked."""

    seen: list = []
    tv = {"screen_on": True, "app": "com.github.damontecres.wholphin", "app_name": "Wholphin (Jellyfin)"}
    agent_reply = "It's **sunny**, see [the forecast](https://example.com)."

    def log_message(self, *args):
        pass

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        Fake.seen.append((self.path, self.headers.get("Authorization"), body))
        if self.path == "/mcp":
            out = {"result": {"content": [{"type": "text", "text": json.dumps(Fake.tv)}]}}
        else:
            out = {"choices": [{"message": {"role": "assistant", "content": Fake.agent_reply}}]}
        data = json.dumps(out).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


class AskTest(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        (self.tmp / "tv-token").write_text("tv-secret\n")
        (self.tmp / "openclaw.json").write_text(json.dumps({"gateway": {"auth": {"token": "gw-secret"}}}))
        self.fake = ThreadingHTTPServer(("127.0.0.1", 0), Fake)
        threading.Thread(target=self.fake.serve_forever, daemon=True).start()
        base = f"http://127.0.0.1:{self.fake.server_address[1]}"
        self.patch = {
            "CONFIG": self.tmp / "ask",
            "GATEWAY": base,
            "MIMIR_TV": base,
            "MIMIR_TV_TOKEN": self.tmp / "tv-token",
            "OPENCLAW_CONFIG": self.tmp / "openclaw.json",
        }
        self.old = {k: getattr(mimir_ask, k) for k in self.patch}
        for k, v in self.patch.items():
            setattr(mimir_ask, k, v)
        os.environ.pop("OPENCLAW_GATEWAY_TOKEN", None)
        self.server = mimir_ask.serve(0)
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        self.url = f"http://127.0.0.1:{self.server.server_address[1]}/ask"
        Fake.seen = []

    def tearDown(self):
        for s in (self.server, self.fake):
            s.shutdown()
            s.server_close()
        for k, v in self.old.items():
            setattr(mimir_ask, k, v)

    def ask(self, text, token=None, json_body=False):
        data = json.dumps({"q": text}).encode() if json_body else text.encode()
        headers = {"Authorization": f"Bearer {token or self.server.token}"}
        headers["Content-Type"] = "application/json" if json_body else "text/plain"
        req = urllib.request.Request(self.url, data=data, headers=headers, method="POST")
        try:
            with urllib.request.urlopen(req, timeout=10) as r:
                return r.status, r.read().decode()
        except urllib.error.HTTPError as e:
            return e.code, e.read().decode()

    def test_only_its_own_token_gets_an_answer_and_the_token_file_is_owner_only(self):
        self.assertEqual(self.ask("what's on tv", token="guess")[0], 401)
        self.assertEqual(Fake.seen, [])
        self.assertEqual((self.tmp / "ask" / "token").stat().st_mode & 0o777, 0o600)

    def test_whats_on_tv_answers_from_mimir_tv_without_the_agent(self):
        Fake.tv = Fake.tv | {
            "playing": {"title": "Episode 3", "show": "Dark", "episode": "S01E03", "paused": False, "minute": 12, "of_minutes": 50}
        }
        self.assertEqual(self.ask("Hey, what's playing on the TV?"), (200, "Dark, S01E03 is playing on the TV, at minute 12 of 50."))
        self.assertEqual([(p, a) for p, a, _ in Fake.seen], [("/mcp", "Bearer tv-secret")])
        Fake.tv = {"screen_on": False, "app": ""}
        self.assertEqual(self.ask("what is on tv", json_body=True), (200, "The TV is off."))

    def test_anything_else_goes_to_the_home_agent_in_the_voice_thread_and_comes_back_speakable(self):
        self.assertEqual(self.ask("Will it rain today?"), (200, "It's sunny, see the forecast."))
        path, auth, body = Fake.seen[-1]
        self.assertEqual((path, auth, body["model"], body["user"]), ("/v1/chat/completions", "Bearer gw-secret", "openclaw/home", "voice"))
        self.assertEqual(body["messages"][-1], {"role": "user", "content": "Will it rain today?"})
        self.assertIn("speech", body["messages"][0]["content"])

    def test_a_failing_agent_says_sorry_instead_of_an_error(self):
        mimir_ask.GATEWAY = "http://127.0.0.1:9"  # nothing listens there
        self.assertEqual(self.ask("anything"), (200, mimir_ask.SORRY))
        self.assertEqual(self.ask("   ")[0], 400)


if __name__ == "__main__":
    unittest.main()
