# CLI Reference

All flags, environment variables, and config file fields for the bootstrap scripts.

For step-by-step installation see [installation.md](installation.md). For common issues see [troubleshooting.md](troubleshooting.md).

---

## Scripts

| Script | Platform | Purpose |
|---|---|---|
| `scripts/bootstrap.sh` | Linux, macOS, WSL, Pi OS | Main wizard (install + configure + pair) |
| `scripts/bootstrap.ps1` | Windows (PowerShell 5.1+) | Main wizard for Windows |
| `scripts/link-claude-projects.sh` | Linux, macOS | Cross-platform symlink helper for `~/.claude/projects/` |

HAOS uses no script — install the Syncthing add-on per [haos-addon.md](haos-addon.md).

---

## Bootstrap flags

### `bootstrap.sh` (Linux/macOS/WSL/Pi OS)

```
./scripts/bootstrap.sh [FLAGS]

  (no flags)        Interactive wizard. Default behavior.
  --reset           Remove peer device entries, folder shares, and
                    config.env. Syncthing stays installed and running.
                    ~/.claude/ data is NOT touched.
  --yes, -y         Non-interactive mode. Read everything from
  --non-interactive config.env, skip all prompts. For scripted deploys
                    or re-runs.
  --no-browser      Don't auto-open the Web UI at the end.
  --help, -h        Show usage.
```

### `bootstrap.ps1` (Windows)

```
.\scripts\bootstrap.ps1 [FLAGS]

  (no flags)        Interactive wizard. Default behavior.
  -Reset            Remove peer device entries, folder shares, and
                    config.env. Syncthing stays installed and running.
                    ~/.claude/ data is NOT touched.
  -Yes, -y          Non-interactive mode. Read everything from
  -NonInteractive   config.env, skip all prompts.
  -NoBrowser        Don't auto-open the Web UI at the end.
  -Help             Show usage.
```

PowerShell parameter binding is case-insensitive: `-reset`, `-Reset`, `-RESET` all work.

---

## What the wizard does (in order)

| Phase | What | Skippable? |
|---|---|---|
| 0 | Welcome banner, platform detection | — |
| 1 | Pre-flight: check `curl`, `python3`, `git`, `sudo`, `systemctl --user` (Linux); `winget`, `git`, PS version (Windows) | warns + asks to continue if anything missing |
| 2 | Install Syncthing if missing (apt / dnf / pacman / brew / winget) | no-op if already installed |
| 3 | Deploy `.stignore`, prompt for optional extra folder, set up autostart, start Syncthing | extra folder only if first run + interactive |
| 4 | Show this device's ID, list existing peers, prompt to add new ones | "Add a peer now?" — answer `n` to skip |
| 5 | Apply config: register devices + create folders via Syncthing API | always runs |
| 5a | Verify connections (poll up to 30s) | only if peers configured |
| 6 | Final summary, copy ID to clipboard, open Web UI | `--no-browser` skips browser open |

---

## `config.env` fields

The bootstrap creates this file from `config.example.env` on first run. Gitignored. Used in non-interactive mode and as memory between runs.

```bash
# Where Claude Code stores its state. Almost always ~/.claude.
CLAUDE_DIR="$HOME/.claude"

# Optional extra sync folder. Empty = skip.
EXTRA_SYNC_DIR=""
EXTRA_SYNC_LABEL="code"   # used as the Syncthing folder ID

# Comma-separated, parallel arrays. Index N in each refers to the same peer.
PEER_IDS="ABCDEFG-...,QRSTUVW-..."        # Syncthing Device IDs (8 groups of 7 chars)
PEER_NAMES="Pi-HA,Laptop"                  # short labels
PEERS_ALWAYS_ON="true,false"               # which peer is the always-on relay (Syncthing introducer)
```

Variables are bash-style (`KEY="value"`) and parsed by both `bootstrap.sh` (via `source`) and `bootstrap.ps1` (via line-by-line regex).

`$HOME` in `CLAUDE_DIR` is expanded on Linux/macOS via shell, on Windows replaced with `$env:USERPROFILE` by the script.

---

## Folder IDs and paths

The wizard creates one or two Syncthing folders, both `sendreceive` type with Trash Can versioning (7 days):

| Folder ID | Path | Source |
|---|---|---|
| `claude` | `$CLAUDE_DIR` (default `~/.claude`) | always created |
| `<EXTRA_SYNC_LABEL>` (default `code`) | `$EXTRA_SYNC_DIR` | only if user provided a path |

**Folder IDs must match across all peers** (including HAOS) for sync to work. If you customize `EXTRA_SYNC_LABEL`, set the same label everywhere.

---

## Device introducer behavior

When you mark a peer as `always-on=yes`, the wizard sets Syncthing's **introducer** flag for that device entry. Effects:

- The introducer's known peers get auto-added to your config
- Adding a new device once on the introducer propagates it to everyone
- If you remove the introducer, devices it introduced get marked accordingly (but not auto-removed)

Per the Syncthing docs: introducer = "I trust this device's device list".

---

## API access (advanced)

The wizard talks to Syncthing's REST API at `http://127.0.0.1:8384/rest/`. The API key lives in Syncthing's `config.xml` (auto-generated).

**Find the API key:**
```bash
# Linux (newer systemd path)
grep -oP '(?<=<apikey>)[^<]+' ~/.local/state/syncthing/config.xml | head -1

# Linux (older default)
grep -oP '(?<=<apikey>)[^<]+' ~/.config/syncthing/config.xml | head -1

# macOS
grep -oP '(?<=<apikey>)[^<]+' "$HOME/Library/Application Support/Syncthing/config.xml" | head -1

# Windows
([xml](Get-Content "$env:LOCALAPPDATA\Syncthing\config.xml")).configuration.gui.apikey
```

**Useful endpoints:**
```bash
APIKEY="<your-api-key>"
BASE="http://127.0.0.1:8384/rest"

# this device's ID
curl -s -H "X-API-Key: $APIKEY" $BASE/system/status | python3 -c "import json,sys;print(json.load(sys.stdin)['myID'])"

# connection state for all peers
curl -s -H "X-API-Key: $APIKEY" $BASE/system/connections | python3 -m json.tool

# folder sync status
curl -s -H "X-API-Key: $APIKEY" "$BASE/db/status?folder=claude" | python3 -m json.tool

# completion percentage from a specific peer
curl -s -H "X-API-Key: $APIKEY" "$BASE/db/completion?folder=claude&device=<peer-id>"
```

Full API docs: <https://docs.syncthing.net/dev/rest.html>

---

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | Generic failure (missing prerequisite, install failed, API key not found) |

The wizard prefers warnings + "continue?" prompts over hard exits, so most non-fatal issues won't bail.

---

## Examples

### Fresh setup on first device
```bash
git clone https://github.com/iceboerg00/claudemirror.git
cd claudemirror
./scripts/bootstrap.sh
```

### Add a peer to an existing setup (any device)
```bash
./scripts/bootstrap.sh
# answer "y" to "Add a peer device now?"
# paste the new peer's Device ID
```

### Re-deploy via existing config (no prompts)
```bash
./scripts/bootstrap.sh --yes
# uses CLAUDE_DIR / EXTRA_SYNC_DIR / PEER_IDS from config.env
```

### Tear down for clean re-setup
```bash
./scripts/bootstrap.sh --reset
# removes peers, folders, config.env. Syncthing stays.
./scripts/bootstrap.sh
# fresh wizard run
```

### Quiet install on a headless server
```bash
./scripts/bootstrap.sh --no-browser
# no Web UI auto-open
```

### Combine
```bash
./scripts/bootstrap.sh --yes --no-browser
# fully unattended after config.env is populated
```

PowerShell equivalents:
```powershell
.\scripts\bootstrap.ps1
.\scripts\bootstrap.ps1 -Reset
.\scripts\bootstrap.ps1 -Yes -NoBrowser
```

---

## See also

- [README](../README.md) — overview and quick start
- [installation.md](installation.md) — detailed walkthroughs per scenario
- [haos-addon.md](haos-addon.md) — HAOS-specific setup (no script)
- [troubleshooting.md](troubleshooting.md) — when things go wrong
