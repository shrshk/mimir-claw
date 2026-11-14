"""mimir-ask: one question in, one short spoken answer out, for Siri (a Shortcut on the iPhone and the Apple Watch).

    POST /ask   Authorization: Bearer <token>   body: the question (text, or JSON {"q": "…"})
    → 200 text/plain: the answer, ready for the Shortcut's Speak Text

Two paths. Known questions go straight to the house's apps and answer in under a second ("what's on TV": mimir-tv).
Anything else goes to OpenClaw's Personal agent (`home`) through the Gateway's OpenAI-style endpoint, in one `voice`
conversation, asked to answer in a sentence or two for speech.

Listens on 127.0.0.1 only (Caddy serves it as ask.home.<domain> to the tailnet). Its own token, made on first start,
is in ~/.config/mimir-ask/token (owner-only): the Shortcut sends it. The Gateway's token stays here, read from
OpenClaw's own config; the phone never has it. Questions and answers are not logged, only which path and how long.
Standard library only: runs with the Mac's python3.
"""

import hmac
import json
import os
import re
import secrets
import sys
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

HOME = Path.home()
CONFIG = Path(os.environ.get("MIMIR_ASK_CONFIG", HOME / ".config/mimir-ask"))
PORT = int(os.environ.get("MIMIR_ASK_PORT", "8728"))
GATEWAY = os.environ.get("MIMIR_ASK_GATEWAY", "http://127.0.0.1:18789")
OPENCLAW_CONFIG = Path(os.environ.get("OPENCLAW_CONFIG", HOME / ".openclaw/openclaw.json"))
MIMIR_TV = os.environ.get("MIMIR_ASK_MIMIR_TV", "http://127.0.0.1:8723")
MIMIR_TV_TOKEN = Path(os.environ.get("MIMIR_ASK_MIMIR_TV_TOKEN", HOME / ".config/mimir-tv/mcp-token"))
AGENT = "openclaw/home"
SESSION = "voice"  # one thread for every spoken ask (OpenClaw keeps its history)
AGENT_WAIT = 55  # seconds: a Shortcut gives up after about a minute
MAX_QUESTION = 2000

VOICE = (
    "This is a spoken question from Siri on the person's iPhone or Apple Watch. Answer for speech: one or two short "
    "sentences, plain words, no lists, links, markdown or emoji. Use the house's tools when they know the answer. "
    "If something needs a choice or a long answer, say so in a sentence and suggest asking in the OpenClaw app."
)
SORRY = "Sorry, I couldn't get an answer just now. Try again in a moment."

TV_QUESTION = re.compile(r"\bwhat(?:'?s| is)\s+(?:on|playing)(?:\s+on)?(?:\s+the)?\s+tv\b|\bwhat(?:'?s| is) playing\b", re.I)


def token() -> str:
    """mimir-ask's own token: made on first start, owner-only."""
    f = CONFIG / "token"
    if not f.exists():
        CONFIG.mkdir(parents=True, exist_ok=True, mode=0o700)
        fd = os.open(f, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, "w") as out:
            out.write(secrets.token_urlsafe(32))
    return f.read_text().strip()


def gateway_token() -> str:
    found = os.environ.get("OPENCLAW_GATEWAY_TOKEN")
    if found:
        return found
    cfg = json.loads(OPENCLAW_CONFIG.read_text())
    return cfg.get("gateway", {}).get("auth", {}).get("token", "")


def post_json(url: str, body: dict, headers: dict, wait: float) -> dict:
    req = urllib.request.Request(
        url, data=json.dumps(body).encode(), headers={"Content-Type": "application/json"} | headers, method="POST"
    )
    with urllib.request.urlopen(req, timeout=wait) as r:
        return json.loads(r.read().decode() or "{}")


def mcp_tool(name: str, args: dict | None = None) -> dict:
    """One of mimir-tv's MCP tools, as OpenClaw calls them."""
    headers = {"Authorization": f"Bearer {MIMIR_TV_TOKEN.read_text().strip()}", "Accept": "application/json"}
    body = {"jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": {"name": name, "arguments": args or {}}}
    result = post_json(f"{MIMIR_TV}/mcp", body, headers, 10)["result"]
    text = result["content"][0]["text"]
    if result.get("isError"):
        raise RuntimeError(text)
    return json.loads(text)


def say_whats_on_tv(now: dict) -> str:
    if not now.get("screen_on"):
        return "The TV is off."
    app = now.get("app_name") or "something"
    playing = now.get("playing")
    if isinstance(playing, dict) and playing.get("title"):
        what = playing["title"]
        if playing.get("show"):
            what = f"{playing['show']}, {playing['episode'] or playing['title']}".rstrip(", ")
        state = "paused at" if playing.get("paused") else "at"
        left = f", {state} minute {playing['minute']} of {playing['of_minutes']}" if playing.get("of_minutes") else ""
        return f"{what} is playing on the TV{left}."
    if playing:
        return f"The TV is on {app}, with nothing playing."
    return f"The TV is on {app}."


FAST = [(TV_QUESTION, lambda: say_whats_on_tv(mcp_tool("whats_on_tv")))]


def speakable(text: str) -> str:
    """The agent's reply for speech: no markdown marks or links."""
    text = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", text)
    text = re.sub(r"[*_`#>]+", "", text)
    return re.sub(r"\s+", " ", text).strip()


def ask_agent(question: str) -> str:
    body = {
        "model": AGENT,
        "user": SESSION,
        "messages": [{"role": "system", "content": VOICE}, {"role": "user", "content": question}],
    }
    out = post_json(
        f"{GATEWAY}/v1/chat/completions", body, {"Authorization": f"Bearer {gateway_token()}"}, AGENT_WAIT
    )
    return speakable(out["choices"][0]["message"]["content"]) or SORRY


def answer(question: str) -> tuple[str, str]:
    """The answer, and which path gave it (for the log)."""
    for pattern, fast in FAST:
        if pattern.search(question):
            try:
                return fast(), "fast"
            except (OSError, KeyError, ValueError, RuntimeError):
                break  # the agent can still try
    try:
        return ask_agent(question), "agent"
    except (OSError, KeyError, ValueError, IndexError):
        return SORRY, "failed"


class Handler(BaseHTTPRequestHandler):
    server_version = "mimir-ask"

    def log_message(self, *args) -> None:  # no request lines (they carry nothing useful, and never the question)
        pass

    def reply(self, code: int, text: str) -> None:
        body = text.encode()
        self.send_response(code)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:
        self.reply(200, "ok") if self.path == "/health" else self.reply(404, "not here")

    def do_POST(self) -> None:
        if self.path != "/ask":
            return self.reply(404, "not here")
        given = self.headers.get("Authorization", "").removeprefix("Bearer ").strip()
        if not hmac.compare_digest(given.encode(), self.server.token.encode()):
            return self.reply(401, "not allowed")
        size = int(self.headers.get("Content-Length") or 0)
        if size <= 0 or size > MAX_QUESTION * 4:
            return self.reply(400, "ask a question")
        raw = self.rfile.read(size).decode("utf-8", "replace")
        if "json" in (self.headers.get("Content-Type") or ""):
            try:
                raw = str(json.loads(raw).get("q", ""))
            except (ValueError, AttributeError):
                return self.reply(400, "ask a question")
        question = raw.strip()[:MAX_QUESTION]
        if not question:
            return self.reply(400, "ask a question")
        start = time.monotonic()
        text, path = answer(question)
        print(f"{time.strftime('%Y-%m-%d %H:%M:%S')} {path} {time.monotonic() - start:.1f}s", flush=True)
        self.reply(200, text)


def serve(port: int = PORT) -> ThreadingHTTPServer:
    server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    server.token = token()
    return server


if __name__ == "__main__":
    s = serve()
    print(f"mimir-ask on 127.0.0.1:{s.server_address[1]}", file=sys.stderr, flush=True)
    s.serve_forever()
