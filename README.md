# claude-code-syncthing

Sync your Claude Code state (`~/.claude/`) — sessions, skills, custom hooks, plans — across multiple devices using [Syncthing](https://syncthing.net/). Live, P2P, end-to-end encrypted, no cloud account required.

> **Requirement:** At least **one device must be always-on**. Syncthing is peer-to-peer — if devices never overlap online, nothing syncs. A desktop that you leave running, a NAS, a Pi, a VPS — anything that's reachable when your laptop comes back from a trip.

---

## Why this exists

Claude Code stores session history, custom skills, plans and tasks under `~/.claude/`. By default this is per-machine. You start a chat on your desktop, take your laptop to a café, run `claude --resume` — and find nothing. This project sets up Syncthing so all your devices share one logical `~/.claude/` (with sane exclusions for caches and platform-specific settings).

Optional: also sync a code directory like `~/code/` or `~/Desktop/projekte/` between devices.

---

## Scenarios

### Scenario A — Two devices, one always-on (recommended for solo devs)

```
[Desktop, always-on]  <-- direct sync -->  [Laptop, mobile]
```

Your desktop stays on. Laptop comes and goes. When laptop is home or anywhere with internet, it syncs to desktop directly. No relay needed if both are on Tailscale or you have port-forwarding for the desktop.

### Scenario B — Two devices + one always-on relay (NAS, Pi, VPS)

```
[Desktop, mobile]                       [Laptop, mobile]
        \                                       /
         \--> [Pi / NAS / VPS, always-on] <----/
```

Use this if **neither** of your main devices is always-on. The relay (Raspberry Pi, Synology NAS, cheap VPS) holds the latest state 24/7. Each device syncs against it whenever it comes online.

### Scenario C — Three devices including a Home Assistant Pi as relay

```
[Desktop]      [Laptop]      [Pi running HAOS, always-on]
       \           |           /
        \----------+----------/
              (Syncthing add-on)
```

Same idea as B, but the always-on node is a Pi running Home Assistant OS. You install the Syncthing add-on from a community repository — see [`docs/haos-addon.md`](docs/haos-addon.md).

---

## ⚡ Quick Start

> **Detailed walkthrough:** [docs/installation.md](docs/installation.md) — prerequisites per platform, scenario-by-scenario steps, expected output, verification checks.

### 1. Clone

```bash
git clone https://github.com/iceboerg00/claude-code-syncthing.git
cd claude-code-syncthing
```

### 2. Run the bootstrap on each device

**Linux / macOS / WSL / Raspberry Pi OS:**
```bash
./scripts/bootstrap.sh
```

**Windows (PowerShell):**
```powershell
.\scripts\bootstrap.ps1
```

**Home Assistant OS:** see [`docs/haos-addon.md`](docs/haos-addon.md) — needs UI clicks, not scriptable from outside.

The bootstrap script does:
1. Install Syncthing if missing
2. Configure autostart (systemd user / Scheduled Task / brew services)
3. Prompt for peer device IDs on first run (saved to `config.env`, gitignored)
4. Use Syncthing's REST API to register peers + create folders with sane defaults (versioning Trash 7d, smart ignore patterns)
5. Cross-platform helper: symlinks Linux/macOS-named Claude project folders to Windows-named ones so `claude --resume` works after syncing from a Windows machine

### 3. Repeat on each device

Each device shows its own Device ID at the end of the bootstrap. Pass them around — or paste them in when prompted on each new device. See the [installation guide](docs/installation.md#4-walkthrough-scenario-a) for the exact prompts and what to enter for your scenario.

---

## What gets synced (and what doesn't)

**Synced from `~/.claude/`:**
- `projects/` — your session histories (the main reason for this project)
- `skills/` — custom skills you created
- `plans/`, `tasks/` — work-in-progress files
- `agents/` (if present) — custom agent definitions

**NOT synced:**
- `settings.json` — paths differ per platform
- `cache/`, `paste-cache/`, `shell-snapshots/`, `session-env/`, `telemetry/`, `debug/`, `downloads/`, `backups/` — volatile per-device
- Platform-specific symlinks (some plugin marketplaces use OS-specific symlinks that break cross-platform)

See [`templates/stignore-claude`](templates/stignore-claude) for the full ignore list.

---

## ⚠️ Important gotchas

### 1. Don't run Claude Code on two devices simultaneously
Both will write to the same `<session>.jsonl` file at once → Syncthing creates `.sync-conflict-*` files. Workflow: close Claude on device A, wait for green status in Syncthing, then open on device B.

### 2. `settings.json` is per-device
Paths like `C:\Users\Mike\.claude\statusline.js` don't exist on Linux. Maintain your settings per platform — don't try to share the file. The bootstrap script does NOT touch your existing `settings.json`.

### 3. Cross-platform Claude session resume needs symlinks
Claude derives the project folder name from the absolute pwd:
- Windows: `C--Users-Mike-Desktop-myproject` 
- Linux:   `-home-mike-Desktop-myproject`

The bootstrap creates symlinks on Linux to make sessions visible. See [`scripts/link-claude-projects.sh`](scripts/link-claude-projects.sh).

### 4. Plugin symlinks may not survive Win ↔ Linux
Some skill installers create symlinks (e.g. `skills/impeccable -> ~/.agents/skills/impeccable`). NTFS handles these differently than ext4. The stignore template excludes the known offenders.

---

## Outside your home network

Syncthing has Global Discovery + Relay enabled by default. Your laptop in a café will find your home Pi via the public Syncthing discovery servers, and connect either directly (if your home router does UPnP / port forwarding for 22000) or via Syncthing's free relays (~100 KB/s, slow but works).

**For best results:** install [Tailscale](https://tailscale.com) on all devices. Then Syncthing connects via stable Tailscale IPs, no port forwarding, no relay. Free for personal use up to 100 devices.

---

## Troubleshooting

See [`docs/troubleshooting.md`](docs/troubleshooting.md).

---

## License

MIT — see [`LICENSE`](LICENSE).

## Credits

Inspired by [tawanorg/claude-sync](https://github.com/tawanorg/claude-sync) (cloud-bucket approach) and the [Poeschl HA add-ons](https://github.com/Poeschl-HomeAssistant-Addons/repository) project. This implementation favours Syncthing P2P over cloud storage for users who want no third-party dependency and live (rather than push/pull) sync.
