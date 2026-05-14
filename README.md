# claude-code-syncthing

> Sync your [Claude Code](https://claude.com/claude-code) state — sessions, skills, custom hooks, plans — across all your devices using [Syncthing](https://syncthing.net/). Live, P2P, end-to-end encrypted, no cloud account.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](#)

---

## What this gives you

- Open Claude Code on your desktop, take your laptop to a café, run `claude --resume` — your full session history is there.
- Skills, plans, custom hooks, agents stay in sync.
- Optional: also sync a code/projects directory between devices.
- Cross-platform: Windows, macOS, Linux, Raspberry Pi OS, Home Assistant OS (as a relay).

## What this is not

- Not a cloud backup. Sync is peer-to-peer. If all your devices die at once, your data dies with them. (Syncthing's trash-can versioning gives you a 7-day local recovery buffer.)
- Not a way to run Claude Code itself remotely. Each device runs its own Claude — they just share state.
- Not a replacement for git. Code projects belong in git; this layer just convenient-syncs work-in-progress files.

---

## Requirement: at least one always-on device

Syncthing is P2P. If two devices never overlap online, no sync happens. So **one of your devices must be always-on**: a desktop you leave running, a Raspberry Pi, a NAS, a small VPS, or a Home Assistant instance.

If neither your desktop nor your laptop is always-on, add a third low-power node (Pi 4, Synology, $3/mo VPS — anything Linux). It holds the latest state 24/7 and lets the others come and go.

---

## Quick Start

### 1. Clone

```bash
git clone https://github.com/iceboerg00/claude-code-syncthing.git
cd claude-code-syncthing
```

### 2. Run the wizard on each device

| Platform | Command |
|---|---|
| Linux / macOS / WSL / Pi OS | `./scripts/bootstrap.sh` |
| Windows (PowerShell) | `.\scripts\bootstrap.ps1` |
| Home Assistant OS | UI clicks — see [`docs/haos-addon.md`](docs/haos-addon.md) |

The wizard installs Syncthing, sets up autostart, configures `~/.claude` as a synced folder, then walks you through pairing with your other devices.

### 3. Recommended order

Always **start on your always-on device** — its Device ID becomes the anchor that all other devices register as a peer.

| Scenario | First | Then |
|---|---|---|
| **A** — 2 devices, desktop always-on | Desktop | Laptop |
| **B** — 3 devices, dedicated Pi/NAS/VPS relay | The relay (SSH in) | Desktop, then laptop |
| **C** — 3 devices, HAOS Pi as relay | HAOS Pi (UI) | Desktop, then laptop |

Each device's wizard prints its Device ID at the end. The next device's wizard asks for that ID.

→ Full step-by-step with sample outputs: [`docs/installation.md`](docs/installation.md)

---

## Wizard flags

```
--reset       remove peer devices + folder shares + config.env (Syncthing stays)
--yes / -y    non-interactive (read everything from config.env)
--no-browser  don't auto-open the Web UI at the end
--help        usage
```

PowerShell uses PascalCase flags: `-Reset`, `-Yes`, `-NoBrowser`, `-Help`.

→ Full reference: [`docs/cli-reference.md`](docs/cli-reference.md)

---

## What's synced

From `~/.claude/`:
- `projects/` — session histories (the main reason for this project)
- `skills/`, `plans/`, `tasks/`, `agents/` — your work-in-progress
- `history.jsonl`, `CLAUDE.md` — global instructions / shell history

Not synced (per [`templates/stignore-claude`](templates/stignore-claude)):
- `settings.json` — paths differ per platform; you maintain it per-device
- `cache/`, `paste-cache/`, `shell-snapshots/`, `session-env/`, `telemetry/`, `debug/`, `downloads/`, `backups/` — volatile per-device
- Plugin/skill symlinks that don't survive Windows ↔ Linux (NTFS vs ext4 differences)

Optional: a code/projects directory you specify during setup. Defaults to no extra folder.

---

## Important gotchas

### Don't run Claude Code on two devices simultaneously
Both devices will write to the same `<session>.jsonl` — Syncthing creates `.sync-conflict-*` files. Workflow: close Claude on device A, wait for green status, then open on device B.

### `settings.json` is per-device
Paths like `C:\Users\Mike\.claude\statusline.js` don't exist on Linux. The wizard does NOT touch your existing `settings.json`. If you have one with hooks/statusLine, maintain a copy per platform yourself.

### Cross-platform Claude project folder names
Claude derives `~/.claude/projects/<id>/` from the absolute pwd:
- Windows: `C--Users-Mike-Desktop-myproject`
- Linux:   `-home-mike-Desktop-myproject`

After syncing from Windows, the bootstrap on Linux/macOS automatically creates symlinks (Linux-name → Windows-name) so `claude --resume` finds existing sessions. Re-run the bootstrap if new project folders appear later.

### Plugin symlinks may break across OS
Some plugin/skill installers create symlinks (e.g. `skills/impeccable -> ~/.agents/skills/impeccable`). NTFS handles those differently than ext4 → sync errors. The default ignore patterns exclude the known offenders; add your own to `~/.claude/.stignore` if you hit new ones.

---

## Outside your home network

Syncthing's **Global Discovery + Relays** are enabled by default. Your laptop in a café finds your home Pi via public discovery servers and connects either directly (if your home router does UPnP / port-forwarding for 22000) or via Syncthing's free relays (~100 KB/s, slow but works).

For best results: install [Tailscale](https://tailscale.com) on all your devices. Syncthing then connects via stable Tailscale IPs — no port-forwarding, no relay, full speed. Free for personal use up to 100 devices.

---

## Troubleshooting

Common issues and fixes: [`docs/troubleshooting.md`](docs/troubleshooting.md).

When in doubt, the nuclear option:
```bash
./scripts/bootstrap.sh --reset    # or .\scripts\bootstrap.ps1 -Reset
```
This removes peer devices, folder shares, and `config.env`. Syncthing stays installed; your `~/.claude/` data is untouched. Re-run the wizard to set up clean.

---

## License

MIT — see [`LICENSE`](LICENSE).

## Credits

Inspired by [tawanorg/claude-sync](https://github.com/tawanorg/claude-sync) (cloud-bucket approach) and the [Poeschl HA add-ons](https://github.com/Poeschl-HomeAssistant-Addons/repository) project. This implementation favours Syncthing P2P over cloud storage for users who want no third-party dependency and live (rather than push/pull) sync.
