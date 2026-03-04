#!/usr/bin/env bash
set -euo pipefail

HOOKS_DIR="$HOME/.claude/hooks"
CONF_FILE="$HOOKS_DIR/notify.conf"
SCRIPT_FILE="$HOOKS_DIR/notify.py"
SETTINGS_FILE="$HOME/.claude/settings.json"

# Resolve source directory (works for both local run and curl pipe)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)" || SCRIPT_DIR=""

# GitHub raw base URL — used as fallback when running via curl pipe
# Replace YOUR_USERNAME before publishing to GitHub
CCN_RAW="${CCN_RAW:-https://raw.githubusercontent.com/kexueyi/claude-code-notify/main}"

echo ""
echo "  Claude Code Notify — Setup"
echo "  =============================="
echo ""

# --- Detect platform ---
if [[ "$(uname -s)" == "Darwin" ]]; then
    PLATFORM="macOS"
else
    PLATFORM="Linux"
fi
echo "  Detected platform: $PLATFORM"
echo ""

# --- 1/3: macOS Notifications ---
echo "  [1/3] macOS Notifications"
if [[ "$PLATFORM" == "macOS" ]]; then
    MACOS_NOTIFY=true
    echo "    Auto-enabled (detected macOS)"
else
    MACOS_NOTIFY=false
    echo "    Skipped (not macOS)"
fi
echo ""

# --- 2/3: Bark Push ---
echo "  [2/3] Bark Push Notifications"
read -rp "    Enable Bark push? [y/N]: " bark_answer
BARK_ENABLED=false
BARK_SERVER="https://api.day.app"
BARK_KEY=""

if [[ "${bark_answer,,}" == "y" || "${bark_answer,,}" == "yes" ]]; then
    BARK_ENABLED=true
    read -rp "    Bark server URL [https://api.day.app]: " bark_server_input
    if [[ -n "$bark_server_input" ]]; then
        BARK_SERVER="$bark_server_input"
    fi
    read -rp "    Bark device key: " BARK_KEY

    if [[ -n "$BARK_KEY" ]]; then
        echo -n "    Testing... "
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
            "${BARK_SERVER%/}/${BARK_KEY}/Claude%20Code%20Notify/Test%20notification%20%E2%9C%85" \
            --max-time 10 2>/dev/null || echo "000")
        if [[ "$HTTP_CODE" == "200" ]]; then
            echo "Push sent!"
        else
            echo "Warning: got HTTP $HTTP_CODE (check server/key)"
        fi
    fi
fi
echo ""

# --- 3/3: Terminal Bell ---
echo "  [3/3] Terminal Bell"
read -rp "    Enable terminal bell? [Y/n]: " bell_answer
if [[ "${bell_answer,,}" == "n" || "${bell_answer,,}" == "no" ]]; then
    TERMINAL_BELL=false
else
    TERMINAL_BELL=true
fi
echo ""

# --- Install files ---
echo "  Installing..."

mkdir -p "$HOOKS_DIR"

# Copy notify.py — local file first, fallback to download (curl pipe mode)
if [[ -n "$SCRIPT_DIR" && -f "$SCRIPT_DIR/notify.py" ]]; then
    cp "$SCRIPT_DIR/notify.py" "$SCRIPT_FILE"
else
    echo "    notify.py not found locally, downloading..."
    curl -fsSL "$CCN_RAW/notify.py" -o "$SCRIPT_FILE"
fi
chmod +x "$SCRIPT_FILE"
echo "    notify.py -> $SCRIPT_FILE"

# Write config
cat > "$CONF_FILE" <<CONF
{
  "macos_notification": $MACOS_NOTIFY,
  "bark": {
    "enabled": $BARK_ENABLED,
    "server": "$BARK_SERVER",
    "key": "$BARK_KEY"
  },
  "terminal_bell": $TERMINAL_BELL
}
CONF
echo "    Config  -> $CONF_FILE"

# --- Merge hooks into settings.json (via inline Python, no jq needed) ---
HOOK_CMD="~/.claude/hooks/notify.py"
python3 - "$SETTINGS_FILE" "$HOOK_CMD" <<'PYEOF'
import json, sys, os, shutil

settings_path = sys.argv[1]
hook_command  = sys.argv[2]

# Load existing settings or start fresh
settings = {}
if os.path.exists(settings_path):
    shutil.copy2(settings_path, settings_path + ".bak")
    try:
        with open(settings_path) as f:
            settings = json.load(f)
    except (json.JSONDecodeError, ValueError):
        print("    Warning: settings.json has invalid JSON — backed up and starting fresh")
        settings = {}
else:
    os.makedirs(os.path.dirname(settings_path), exist_ok=True)

if not isinstance(settings, dict):
    settings = {}

hooks = settings.setdefault("hooks", {})
hook_entry = {"type": "command", "command": hook_command, "timeout": 5000}

for event in ("Stop", "Notification"):
    event_list = hooks.setdefault(event, [])

    # Idempotent: check if our hook already exists (match by command path)
    found = False
    for group in event_list:
        for h in group.get("hooks", []):
            if h.get("command", "") == hook_command:
                h["timeout"] = hook_entry["timeout"]   # update timeout
                found = True
                break
        if found:
            break

    if not found:
        event_list.append({"hooks": [dict(hook_entry)]})

with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2)
    f.write("\n")
PYEOF
echo "    Hooks merged into $SETTINGS_FILE"

echo ""
echo "  Done! Restart Claude Code to activate."
echo ""
