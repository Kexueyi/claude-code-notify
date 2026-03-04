#!/usr/bin/env python3
"""Claude Code hook notification script.

Sends notifications when Claude Code stops or needs attention.
Supports macOS native notifications, Bark push, and terminal bell.

Config: ~/.claude/hooks/notify.conf (JSON)
"""
import json
import os
import subprocess
import sys
import urllib.parse
import urllib.request

CONFIG_PATH = os.path.expanduser("~/.claude/hooks/notify.conf")

DEFAULT_CONFIG = {
    "macos_notification": True,
    "bark": {"enabled": False, "server": "https://api.day.app", "key": ""},
    "terminal_bell": True,
}


def load_config():
    try:
        with open(CONFIG_PATH) as f:
            user = json.load(f)
        # Merge with defaults
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


def main():
    data = json.load(sys.stdin)
    event = data.get("hook_event_name", "")
    cwd = data.get("cwd", "")
    project = os.path.basename(cwd) if cwd else "project"

    if event == "Stop":
        msg = data.get("last_assistant_message", "Done") or "Done"
        title = f"\U0001f916 {project} \u2705"
        body = msg[:80].replace("\n", " ")
    elif event == "Notification":
        msg = data.get("message", "Needs attention") or "Needs attention"
        body = msg[:80].replace("\n", " ")
        ntype = data.get("notification_type", "")
        if ntype == "permission_prompt":
            title = f"\U0001f916 {project} \U0001f510"
        elif ntype == "idle_prompt":
            title = f"\U0001f916 {project} \u23f3"
        else:
            title = f"\U0001f916 {project} \u2757"
    else:
        return

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


if __name__ == "__main__":
    main()
