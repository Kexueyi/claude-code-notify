#!/usr/bin/env bash
set -euo pipefail

HOOKS_DIR="$HOME/.claude/hooks"
CONF_FILE="$HOOKS_DIR/notify.conf"
SCRIPT_FILE="$HOOKS_DIR/notify.py"
SETTINGS_FILE="$HOME/.claude/settings.json"

echo ""
echo "  Claude Code Notify — Uninstall"
echo "  ================================"
echo ""

# Remove hook files
if [[ -f "$SCRIPT_FILE" ]]; then
    rm "$SCRIPT_FILE"
    echo "  Removed $SCRIPT_FILE"
else
    echo "  $SCRIPT_FILE not found (skipped)"
fi

if [[ -f "$CONF_FILE" ]]; then
    rm "$CONF_FILE"
    echo "  Removed $CONF_FILE"
else
    echo "  $CONF_FILE not found (skipped)"
fi

# Remove hooks from settings.json (via inline Python, no jq needed)
HOOK_CMD="~/.claude/hooks/notify.py"
if [[ -f "$SETTINGS_FILE" ]]; then
    python3 - "$SETTINGS_FILE" "$HOOK_CMD" <<'PYEOF'
import json, sys, os, shutil

settings_path = sys.argv[1]
hook_command  = sys.argv[2]

try:
    with open(settings_path) as f:
        settings = json.load(f)
except (json.JSONDecodeError, ValueError, FileNotFoundError):
    sys.exit(0)

if not isinstance(settings, dict):
    sys.exit(0)

# Backup before modifying
shutil.copy2(settings_path, settings_path + ".bak")

hooks = settings.get("hooks", {})
modified = False

for event in ("Stop", "Notification"):
    event_list = hooks.get(event, [])
    new_list = []
    for group in event_list:
        filtered = [h for h in group.get("hooks", [])
                    if h.get("command", "") != hook_command]
        if filtered:
            new_list.append({"hooks": filtered})
        elif group.get("hooks"):
            modified = True
    if new_list != event_list:
        modified = True
    if new_list:
        hooks[event] = new_list
    elif event in hooks:
        del hooks[event]
        modified = True

if modified:
    with open(settings_path, "w") as f:
        json.dump(settings, f, indent=2)
        f.write("\n")
PYEOF
    echo "  Cleaned hooks from $SETTINGS_FILE"
fi

echo ""
echo "  Done! Claude Code Notify has been removed."
echo ""
