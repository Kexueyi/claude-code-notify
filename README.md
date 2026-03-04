# claude-code-notify

Get notified when [Claude Code](https://docs.anthropic.com/en/docs/claude-code) finishes a task or needs your attention.

Supports **macOS native notifications**, **Bark push** (iOS/Android), and **terminal bell** (great for SSH sessions).

## One-Line Install

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/<kexueyi>/claude-code-notify/main/install.sh)"
```

Or clone and run:

```bash
git clone https://github.com/<kexueyi>/claude-code-notify.git
cd claude-code-notify
./install.sh
```

The interactive installer will guide you through enabling each notification channel.

## Notification Channels

| Channel | Platform | Use Case |
|---------|----------|----------|
| macOS Notification | macOS | Desktop banner + sound |
| Bark Push | Any (iOS/Android) | Mobile push via [Bark](https://github.com/Finb/Bark) |
| Terminal Bell | Any | `\a` to `/dev/tty` — SSH clients show a visual alert |

## Manual Installation

If you prefer to install manually:

**1. Copy the script:**

```bash
mkdir -p ~/.claude/hooks
cp notify.py ~/.claude/hooks/notify.py
chmod +x ~/.claude/hooks/notify.py
```

**2. Create config at `~/.claude/hooks/notify.conf`:**

```json
{
  "macos_notification": true,
  "bark": {
    "enabled": false,
    "server": "https://api.day.app",
    "key": "your-bark-key"
  },
  "terminal_bell": true
}
```

**3. Add hooks to `~/.claude/settings.json`:**

Add these entries to the `"hooks"` object (create it if it doesn't exist):

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/notify.py",
            "timeout": 5000
          }
        ]
      }
    ],
    "Notification": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/notify.py",
            "timeout": 5000
          }
        ]
      }
    ]
  }
}
```

**4. Restart Claude Code.**

## Configuration

Edit `~/.claude/hooks/notify.conf`:

| Field | Type | Description |
|-------|------|-------------|
| `macos_notification` | bool | Enable macOS native notifications (auto-skipped on Linux) |
| `bark.enabled` | bool | Enable Bark push notifications |
| `bark.server` | string | Bark server URL (default: `https://api.day.app`) |
| `bark.key` | string | Your Bark device key |
| `terminal_bell` | bool | Send `\a` to terminal (useful over SSH) |

## Hook Events

| Event | When |
|-------|------|
| `Stop` | Claude finishes a response |
| `Notification` (permission_prompt) | Claude needs permission to run a tool |
| `Notification` (idle_prompt) | Claude is waiting for input |

## Dependencies

**Zero.** Only Python 3 (ships with macOS and most Linux distros) and the Python standard library. No `pip install`, no `jq`, no `node`.

## Testing

Send a test notification manually:

```bash
echo '{"hook_event_name":"Stop","cwd":"/tmp/test","last_assistant_message":"hello world"}' | ~/.claude/hooks/notify.py
```

## Uninstall

```bash
cd claude-code-notify
./uninstall.sh
```

This removes `notify.py`, `notify.conf`, and cleans the hook entries from `settings.json`. Your other settings and hooks are preserved.

## License

MIT
