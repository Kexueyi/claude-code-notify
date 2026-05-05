#!/usr/bin/env python3
"""CLI coding assistant notification hook.

Sends notifications when Claude Code, Gemini CLI, or Codex CLI
finishes a task or needs attention.

Supports macOS native notifications, Bark push, and terminal bell.

Config: ~/.config/claude-code-notify/notify.conf (JSON)

Input methods:
  - Claude Code / Gemini CLI: JSON on stdin
  - Codex CLI: JSON as argv[1]
"""
import json
import os
import subprocess
import sys
import urllib.parse
import urllib.request

CONFIG_PATH = os.path.expanduser("~/.config/claude-code-notify/notify.conf")

DEFAULT_CONFIG = {
    "macos_notification": True,
    "bark": {"enabled": False, "server": "https://api.day.app", "key": ""},
    "terminal_bell": True,
}


def load_config():
    try:
        with open(CONFIG_PATH) as f:
            user = json.load(f)
        cfg = dict(DEFAULT_CONFIG)
        cfg.update(user)
        if isinstance(user.get("bark"), dict):
            bark = dict(DEFAULT_CONFIG["bark"])
            bark.update(user["bark"])
            cfg["bark"] = bark
        return cfg
    except (FileNotFoundError, json.JSONDecodeError):
        return dict(DEFAULT_CONFIG)


def send_macos(title, body):
    """Send macOS native notification via osascript."""
    as_title = title.replace("\\", "\\\\").replace('"', '\\"')
    as_body = body.replace("\\", "\\\\").replace('"', '\\"')
    script = f'display notification "{as_body}" with title "{as_title}" sound name "Ping"'
    subprocess.Popen(
        ["osascript", "-e", script],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def send_bark(title, body, server, key):
    """Send Bark push notification."""
    encoded_title = urllib.parse.quote(title)
    encoded_body = urllib.parse.quote(body)
    url = f"{server.rstrip('/')}/{key}/{encoded_title}/{encoded_body}"
    try:
        urllib.request.urlopen(url, timeout=5)
    except Exception:
        pass


def send_bell():
    """Send terminal bell character to /dev/tty."""
    try:
        with open("/dev/tty", "w") as tty:
            tty.write("\a")
            tty.flush()
    except (OSError, IOError):
        pass


def read_input():
    """Read hook data from argv[1] (Codex) or stdin (Claude/Gemini)."""
    if len(sys.argv) > 1:
        return json.loads(sys.argv[1])
    return json.load(sys.stdin)


def normalize(data):
    """Normalize event data from all 3 CLIs into (title, body) or None.

    Event mapping:
      Stop (Claude)              -> task-complete
      AfterAgent (Gemini)        -> task-complete (skip if has_pending_tool_calls)
      agent-turn-complete (Codex) -> task-complete
      Notification (Claude/Gemini) -> attention-needed
    """
    # Determine event name — Claude/Gemini use hook_event_name, Codex uses type
    event = data.get("hook_event_name") or data.get("type", "")

    cwd = data.get("cwd", "")
    project = os.path.basename(cwd) if cwd else "project"

    # --- Task complete events ---
    if event == "Stop":
        # Claude Code
        msg = data.get("last_assistant_message", "Done") or "Done"
        title = f"\U0001f916 {project} \u2705"
        body = msg[:80].replace("\n", " ")
        return title, body

    if event == "AfterAgent":
        # Gemini CLI — skip if agent still has pending tool calls
        if data.get("has_pending_tool_calls"):
            return None
        msg = data.get("prompt_response", "Done") or "Done"
        title = f"\U0001f916 {project} \u2705"
        body = msg[:80].replace("\n", " ")
        return title, body

    if event == "agent-turn-complete":
        # Codex CLI (kebab-case fields)
        msg = data.get("last-assistant-message", "Done") or "Done"
        title = f"\U0001f916 {project} \u2705"
        body = msg[:80].replace("\n", " ")
        return title, body

    # --- Attention-needed events ---
    if event == "Notification":
        # Claude Code & Gemini CLI
        ntype = data.get("notification_type", "")
        # Skip idle_prompt \u2014 not useful to notify on
        if ntype == "idle_prompt":
            return None
        msg = data.get("message", "Needs attention") or "Needs attention"
        body = msg[:80].replace("\n", " ")
        if ntype in ("permission_prompt", "ToolPermission"):
            title = f"\U0001f916 {project} \U0001f510"
        else:
            title = f"\U0001f916 {project} \u2757"
        return title, body

    return None


def main():
    data = read_input()
    result = normalize(data)

    if result is None:
        # Always print {} for Gemini compatibility
        print("{}")
        return

    title, body = result
    cfg = load_config()

    # 1. macOS native notification
    if cfg.get("macos_notification") and sys.platform == "darwin":
        send_macos(title, body)

    # 2. Bark push
    bark = cfg.get("bark", {})
    if bark.get("enabled") and bark.get("key"):
        send_bark(title, body, bark.get("server", "https://api.day.app"), bark["key"])

    # 3. Terminal bell
    if cfg.get("terminal_bell"):
        send_bell()

    # Print {} to stdout (required by Gemini, harmless for others)
    print("{}")


if __name__ == "__main__":
    main()
