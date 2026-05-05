#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="$HOME/.config/claude-code-notify"
CONF_FILE="$INSTALL_DIR/notify.conf"
SCRIPT_FILE="$INSTALL_DIR/notify.py"

# Legacy paths (pre-multi-CLI)
LEGACY_DIR="$HOME/.claude/hooks"
LEGACY_SCRIPT="$LEGACY_DIR/notify.py"
LEGACY_CONF="$LEGACY_DIR/notify.conf"
LEGACY_HOOK_CMD="~/.claude/hooks/notify.py"

# Tool config paths
CLAUDE_SETTINGS="$HOME/.claude/settings.json"
GEMINI_SETTINGS="$HOME/.gemini/settings.json"
CODEX_CONFIG="$HOME/.codex/config.toml"

# Hook command (using ~ for JSON configs, full path for TOML)
HOOK_CMD="~/.config/claude-code-notify/notify.py"
HOOK_CMD_FULL="$INSTALL_DIR/notify.py"

# Resolve source directory (works for both local run and curl pipe)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)" || SCRIPT_DIR=""

# GitHub raw base URL — used as fallback when running via curl pipe
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

# --- Detect available tools ---
HAS_CLAUDE=false
HAS_GEMINI=false
HAS_CODEX=false

if [[ -d "$HOME/.claude" ]]; then HAS_CLAUDE=true; fi
if [[ -d "$HOME/.gemini" ]]; then HAS_GEMINI=true; fi
if [[ -d "$HOME/.codex" ]];  then HAS_CODEX=true;  fi

echo -n "  Detected tools:"
$HAS_CLAUDE && echo -n " Claude Code"
$HAS_GEMINI && echo -n " Gemini CLI"
$HAS_CODEX  && echo -n " Codex CLI"
if ! $HAS_CLAUDE && ! $HAS_GEMINI && ! $HAS_CODEX; then
    echo -n " (none — will install shared files only)"
fi
echo ""
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
    echo ""
    echo "    Open the Bark app on your phone to get your push key."
    echo "    It shows a full URL — paste the whole thing below."
    echo ""
    read -rp "    Bark URL or key: " bark_input

    if [[ -n "$bark_input" ]]; then
        # Accept full URL (e.g. https://api.day.app/YOUR_KEY) or raw key
        if [[ "$bark_input" == http* ]]; then
            # Extract server and key from URL: https://server/key/optional...
            bark_proto_server="${bark_input%%/http*}"  # handle double-https by accident
            # Strip trailing slashes and extract components
            cleaned="${bark_input%/}"
            # Remove protocol prefix
            without_proto="${cleaned#https://}"
            without_proto="${without_proto#http://}"
            # Split into server and key
            BARK_SERVER="https://${without_proto%%/*}"
            # The key is the first path segment after the host
            path_part="${without_proto#*/}"
            BARK_KEY="${path_part%%/*}"
        else
            BARK_KEY="$bark_input"
        fi
    fi

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

# --- Install shared files ---
echo "  Installing shared files..."

mkdir -p "$INSTALL_DIR"

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

# --- Legacy migration ---
if [[ -f "$LEGACY_SCRIPT" ]]; then
    rm -f "$LEGACY_SCRIPT"
    echo "    Removed legacy $LEGACY_SCRIPT"
fi
if [[ -f "$LEGACY_CONF" ]]; then
    rm -f "$LEGACY_CONF"
    echo "    Removed legacy $LEGACY_CONF"
fi

# ============================================================
#  Claude Code — merge hooks into settings.json
# ============================================================
if $HAS_CLAUDE; then
    echo ""
    echo "  Configuring Claude Code..."
    python3 - "$CLAUDE_SETTINGS" "$HOOK_CMD" "$LEGACY_HOOK_CMD" <<'PYEOF'
import json, sys, os, shutil

settings_path = sys.argv[1]
hook_command  = sys.argv[2]
legacy_cmd    = sys.argv[3]

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

    # Remove legacy hook entries
    new_list = []
    for group in event_list:
        filtered = [h for h in group.get("hooks", [])
                    if h.get("command", "") != legacy_cmd]
        if filtered:
            new_list.append({"hooks": filtered})
    event_list[:] = new_list

    # Idempotent: check if new hook already exists
    found = False
    for group in event_list:
        for h in group.get("hooks", []):
            if h.get("command", "") == hook_command:
                h["timeout"] = hook_entry["timeout"]
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
    echo "    Hooks merged into $CLAUDE_SETTINGS"
fi

# ============================================================
#  Gemini CLI — merge hooks into settings.json (same structure)
# ============================================================
if $HAS_GEMINI; then
    echo ""
    echo "  Configuring Gemini CLI..."
    python3 - "$GEMINI_SETTINGS" "$HOOK_CMD" <<'PYEOF'
import json, sys, os, shutil

settings_path = sys.argv[1]
hook_command  = sys.argv[2]

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

for event in ("AfterAgent", "Notification"):
    event_list = hooks.setdefault(event, [])

    # Idempotent: check if hook already exists
    found = False
    for group in event_list:
        for h in group.get("hooks", []):
            if h.get("command", "") == hook_command:
                h["timeout"] = hook_entry["timeout"]
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
    echo "    Hooks merged into $GEMINI_SETTINGS"
fi

# ============================================================
#  Codex CLI — add notify hook to config.toml
# ============================================================
if $HAS_CODEX; then
    echo ""
    echo "  Configuring Codex CLI..."
    python3 - "$CODEX_CONFIG" "$HOOK_CMD_FULL" <<'PYEOF'
import sys, os, re, shutil

config_path = sys.argv[1]
hook_full   = sys.argv[2]

notify_line = f'notify = ["python3", "{hook_full}"]'

content = ""
if os.path.exists(config_path):
    shutil.copy2(config_path, config_path + ".bak")
    with open(config_path) as f:
        content = f.read()
else:
    os.makedirs(os.path.dirname(config_path), exist_ok=True)

# Idempotent: check if notify line already exists
if re.search(r'^notify\s*=', content, re.MULTILINE):
    # Update existing notify line
    content = re.sub(r'^notify\s*=.*$', notify_line, content, flags=re.MULTILINE)
else:
    # Append notify line
    if content and not content.endswith("\n"):
        content += "\n"
    content += notify_line + "\n"

with open(config_path, "w") as f:
    f.write(content)
PYEOF
    echo "    Hook added to $CODEX_CONFIG"
fi

echo ""
echo "  Done! Restart your coding assistant to activate."
echo ""
