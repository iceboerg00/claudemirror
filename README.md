# claude-code-syncthing

> Sync your [Claude Code](https://claude.com/claude-code) **state** (sessions, skills, plans, agents, plugins) **and your project folders** across all your devices using [Syncthing](https://syncthing.net/). Live, P2P, end-to-end encrypted, no cloud account.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](#)

---

## What this gives you

- Open Claude Code on your desktop, take your laptop to a café, run `claude --resume` — your full session history is there.
- **Your project folders sync too** — work on the same code on any device without juggling git pulls, USB sticks, or "where did I leave off?".
- Skills, plans, agents, plugins stay in sync across devices.
- Smart `.stignore` defaults exclude the noise: `node_modules`, build artifacts, `.venv`, secrets, IDE junk — only what you actually edit moves.
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

The wizard installs Syncthing, sets up autostart, configures `~/.claude` as a synced folder, **asks if you also want to sync a project/code directory** (e.g. `~/Desktop/projekte`, `~/code`), then walks you through pairing with your other devices.

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

Two synced folders by default — both treated as first-class.

### Folder 1: `~/.claude/` (Claude state) — always synced

| Synced | Not synced (in [stignore-claude](templates/stignore-claude)) |
|---|---|
| `projects/` — session histories | `settings.json`, `settings.local.json` — paths differ per platform |
| `skills/`, `plans/`, `tasks/`, `agents/` | `cache/`, `paste-cache/`, `shell-snapshots/`, `session-env/`, `telemetry/`, `debug/`, `downloads/`, `backups/` — volatile |
| `history.jsonl`, `CLAUDE.md` | Plugin/skill symlinks known to break Win ↔ Linux (e.g. `skills/impeccable`) |
| `plugins/` (full, can be hundreds of MB) | |
| `hooks/` and other root-level scripts | |

### Folder 2: a project/code directory — opt-in during setup

The wizard asks for a path (e.g. `~/Desktop/projekte`, `~/code`). If you provide one, it's synced as a second Syncthing folder with sensible code-project ignores ([stignore-extra](templates/stignore-extra)):

| Synced | Not synced |
|---|---|
| Source files, configs, docs, READMEs | `node_modules/`, `.next/`, `.nuxt/`, `dist/`, `build/`, `target/`, `.dart_tool/` |
| Lockfiles (`package-lock.json` etc.) | `__pycache__/`, `.venv/`, `.pytest_cache/`, `.ruff_cache/` |
| `.gitignore`, `.editorconfig` etc. | `*.pem`, `*.key` — keys/certs stay device-local |
| `.env` files (synced by default) | |
| | `.idea/`, `.vscode/`, `*.swp` — IDE state |
| | `.DS_Store`, `Thumbs.db`, build logs |

Skip this entirely if you'd rather only sync Claude state and keep code in git.

#### Why is X not synced if I need it on the other device?

Most "excluded" items are things you **don't need to sync** because they regenerate locally:

| Excluded | Why | How you get it on the other device |
|---|---|---|
| `node_modules/`, `.venv/`, `dist/`, `build/`, `target/`, `.dart_tool/` | Often huge (hundreds of MB to GBs); contain platform-specific binaries (Linux `.so` ≠ Windows `.dll`); changes constantly during development | Source files + lockfiles **are** synced. Run `npm install` / `pip install -r requirements.txt` / `cargo build` once on the other device — same env in 30s |
| `__pycache__/`, `.pytest_cache/`, `.ruff_cache/` | Regenerated automatically | Just run your code/tests, they rebuild instantly |
| `.idea/`, `.vscode/` (workspace state, not project settings) | Per-machine UI state (window positions, breakpoints, recent files) | Re-open the project — IDE figures it out |
| `*.pem`, `*.key` | Cryptographic keys / certs are device-specific and a higher-stakes leak target | Generate / install per device, or use a dedicated secrets manager |
| `.env` files | **Not excluded by default** — synced like other source files | If you keep production secrets in `.env`, add it to your folder's `.stignore` to opt out per-device |
| `.DS_Store`, `Thumbs.db` | OS-specific file-system metadata, no value cross-platform | Generated automatically by Finder/Explorer when you open the folder |

**Customize:** the `.stignore` file in each synced folder is just a text file — edit it on any device and Syncthing picks up the change automatically. Add patterns to exclude more, or remove lines to sync things the defaults skip.

### Important caveats

- **`hooks/` and similar custom scripts sync the files but not their registration.** Hook activation lives in `settings.json` (per-device) with hardcoded paths like `C:/Users/USER/.claude/hooks/...`. To activate on another platform, add the correct path in that platform's `settings.json`.
- **`plugins/` includes platform binaries.** Some plugins ship native libraries (`.dll`/`.so`) that won't work cross-OS. Re-install affected plugins per-platform via Claude's plugin command — it fetches the right architecture.
- **Project folder sync ≠ git replacement.** Sync moves bytes between your devices in real-time, including uncommitted work. Push to git for shareable, history-tracked snapshots.

---

## Important gotchas

### Don't run Claude Code on two devices simultaneously
Both devices will write to the same `<session>.jsonl` — Syncthing creates `.sync-conflict-*` files. Workflow: close Claude on device A, wait for green status, then open on device B.

### `settings.json` is per-device
Paths inside `settings.json` (e.g. hook commands, statusLine command) reference absolute paths like `C:\Users\USER\.claude\...` which don't exist on Linux. The wizard does NOT touch your existing `settings.json`. If yours has hooks or a statusLine, maintain a copy per platform yourself.

### Cross-platform Claude project folder names
Claude derives `~/.claude/projects/<id>/` from the absolute pwd:
- Windows: `C--Users-USER-Desktop-myproject`
- Linux:   `-home-USER-Desktop-myproject`

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
