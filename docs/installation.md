# Installation Guide

Full step-by-step walkthrough. For a one-screen summary see the [README](../README.md). Flag reference: [cli-reference.md](cli-reference.md). Common issues: [troubleshooting.md](troubleshooting.md).

---

## Table of Contents

1. [Before you start](#1-before-you-start)
2. [Choose your scenario](#2-choose-your-scenario)
3. [Per-platform prerequisites](#3-per-platform-prerequisites)
4. [Walkthrough: Scenario A — Two devices, one always-on](#4-walkthrough-scenario-a)
5. [Walkthrough: Scenario B — Three devices with a dedicated relay](#5-walkthrough-scenario-b)
6. [Walkthrough: Scenario C — HAOS as the relay](#6-walkthrough-scenario-c)
7. [Verifying your install](#7-verifying-your-install)
8. [Adding a new device later](#8-adding-a-new-device-later)
9. [Optional hardening](#9-optional-hardening)
10. [Common first-run issues](#10-common-first-run-issues)

---

## 1. Before you start

### What this installs

- **Syncthing** on each device (~30 MB)
- **Autostart**: systemd user service (Linux), `brew services` (macOS), Scheduled Task (Windows)
- **`.stignore`** in `~/.claude/` so caches and platform-specific files don't sync
- Optional: same `.stignore` style in an additional code/projects directory
- **`config.env`** in the repo (gitignored) holding your peer Device IDs

### What this does NOT touch

- Your existing `~/.claude/settings.json` — left exactly as-is. Settings differ between platforms.
- Your existing `~/.claude/projects/` content — only new data flows in via sync.
- Anything outside `~/.claude/` (and your optional extra folder).

### Decisions to make beforehand

| Decision | Options |
|---|---|
| **Always-on device?** | A desktop you leave running, a NAS, a Pi 4/5, a small VPS, an HAOS instance. Required — sync only happens between devices that overlap online. |
| **Extra folder?** | Sync code too? Pick a path (e.g. `~/Desktop/projekte`, `~/code`). Optional. |
| **GUI auth?** | Default Syncthing GUI is bound to `127.0.0.1` only — local-only access. Setting a user/password is recommended for defense-in-depth, especially if you ever expose the port (Tailscale, reverse proxy). See [Optional hardening](#9-optional-hardening). |

---

## 2. Choose your scenario

```
                Is at least one of your everyday devices on 24/7?
                       /                        \
                      YES                       NO
                       |                         |
                       v                         v
              Scenario A (2 devices)    Need a relay -> Scenario B or C
                                                          /          \
                                                     dedicated   HAOS Pi
                                                     Pi/NAS/VPS     |
                                                                    v
                                                                Scenario C
```

| Scenario | Devices | Always-on node | Start order |
|---|---|---|---|
| **A** | 2 (desktop + laptop) | the desktop | desktop → laptop |
| **B** | 3 (desktop + laptop + Pi/NAS/VPS) | the relay | relay → desktop → laptop |
| **C** | 3 (desktop + laptop + HAOS Pi) | the HAOS Pi | HAOS UI → desktop → laptop |

You can start with A and add a relay later — just re-run the bootstrap on each device with the new peer's ID.

---

## 3. Per-platform prerequisites

The wizard's **Phase 1** runs pre-flight checks and warns you about missing tools.

### Linux (Debian/Ubuntu/Pi OS)

```bash
sudo apt-get update
sudo apt-get install -y curl python3 git
```

The bootstrap installs Syncthing itself from the official APT repository.

**Optional clipboard auto-copy** — install one of:
```bash
sudo apt-get install -y xclip            # X11
sudo apt-get install -y wl-clipboard     # Wayland
```
Without it, the wizard still works — you just have to copy the Device ID with the mouse.

**WSL note:** `systemctl --user` requires systemd. WSL2 + Ubuntu 22.04+ has it by default. WSL1 doesn't — wizard will detect this and skip autostart (warning shown).

### Linux (Fedora/Arch)

The bootstrap auto-detects the package manager.

```bash
# Fedora
sudo dnf install -y curl python3 git xclip
# Arch
sudo pacman -S curl python git xclip
```

### macOS

You need Homebrew. The pre-flight checks for it.

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

`pbcopy` (clipboard) is built in — auto-copy works out of the box.

### Windows

Open a regular (non-admin) PowerShell window.

```powershell
winget --version           # ships with Windows 10/11 "App Installer"
git --version              # winget install --id Git.Git -e if missing
$PSVersionTable.PSVersion  # 5.1 (default) or 7+ both work
```

The wizard installs Syncthing via winget. No admin rights needed — winget installs per-user. `Set-Clipboard` (clipboard auto-copy) is built in.

### HAOS (Pi running Home Assistant OS)

No script — the wizard cannot reach into HAOS. You install Syncthing as a community add-on via the HA web UI. See [`haos-addon.md`](haos-addon.md).

---

## 4. Walkthrough: Scenario A

**Setup:** 1 always-on desktop + 1 mobile laptop.

### Step 1 — Clone on the desktop

```bash
git clone https://github.com/iceboerg00/claude-code-syncthing.git
cd claude-code-syncthing
```

### Step 2 — Run the wizard

Linux/macOS:
```bash
./scripts/bootstrap.sh
```
Windows:
```powershell
.\scripts\bootstrap.ps1
```

Sample output (5 phases):

```
   +-------------------------------------------------------------+
   |       claude-code-syncthing  --  Setup Wizard               |
   +-------------------------------------------------------------+

  Platform: linux  host: desktop

  This wizard will: install Syncthing, set up autostart, configure
  sync of ~/.claude, and walk you through pairing other devices.

  At least one device must be always-on (desktop, Pi, NAS, HAOS).

  Press Enter to continue (or Ctrl-C to abort)

============================================================
  PHASE 1/5 -- Pre-flight checks
============================================================

  ✓ curl
  ✓ python3
  ✓ git
  ✓ sudo
  ✓ systemctl --user

============================================================
  PHASE 2/5 -- Install Syncthing
============================================================

  ✓ Syncthing installed

============================================================
  PHASE 3/5 -- Configure this device
============================================================

  Optional: also sync a code/projects directory between devices.
  (e.g. ~/Desktop/projekte, ~/code -- leave blank to skip)
  Extra folder path: ~/code
  ✓ Path exists: /home/mike/code
  Label for this folder [code]:
  ✓ /home/mike/.claude/.stignore
  ✓ /home/mike/code/.stignore
  ✓ syncthing.service enabled and started
  Waiting for Syncthing API ✓

============================================================
  PHASE 4/5 -- Pair with another device
============================================================

  Your device ID is:

  ABCDEFG-HIJKLMN-OPQRSTU-VWXYZ12-3456789-ABCDEFG-HIJKLMN-OPQRST7
  (copied to clipboard)

  Add a peer device now? [y/N]: n

============================================================
  PHASE 5/5 -- Apply Syncthing config
============================================================

  Configuring folders...
  ✓ folder claude (post): synced with 0 peer(s)
  ✓ folder code (post):   synced with 0 peer(s)

============================================================
  ✓ Setup complete on this device
============================================================

  This device's ID:  ABCDEFG-HIJKLMN-OPQRSTU-VWXYZ12-3456789-...
  (also in your clipboard)

  Web UI:        http://127.0.0.1:8384
  Config file:   /home/mike/claude-code-syncthing/config.env

  Tip: ./scripts/bootstrap.sh --reset to undo. --help for more flags.
```

The wizard auto-opens the Web UI in your browser at the end (`--no-browser` to skip).

**Copy the Device ID.** It's already in your clipboard.

### Step 3 — Clone + bootstrap on the laptop

Same clone command. When the wizard asks "Add a peer device now?" — answer **y** and paste the desktop's Device ID:

```
  Add a peer device now? [y/N]: y

+--- Set up the OTHER device, then come back here: -----------------+

  Linux / macOS / Windows -- clone this repo and run the wizard:
    [boxes with git clone, cd, bootstrap commands]

  HAOS Pi -- install the Syncthing add-on (UI, no script).
    -> docs/haos-addon.md

  Either way, the other device will SHOW its Device ID.
  If asked for YOUR ID, paste: <YOUR LAPTOP ID>
  (HAOS auto-accepts, no paste needed.)

  Come back here when you have the other device's Device ID.

  Press Enter to continue
  Other device's ID (or 'done'): ABCDEFG-HIJKLMN-OPQRSTU-VWXYZ12-3456789-ABCDEFG-HIJKLMN-OPQRST7
  Name for this peer [Peer-1]: Desktop
  Is this peer always-on (a desktop/Pi that stays running)? [y/N]: y
  ✓ Added: Desktop (ABCDEFG…) always-on=true

  Add another peer? [y/N]: n
  ✓ Config saved

  ... [Phase 5 applies, then verifies connection] ...

  ✓ Desktop: connected
```

If the desktop isn't online, the verification phase warns:
```
  ! Desktop: not yet connected (peer must be online and have YOUR ID configured)
```

That's fine — go back to the desktop and add the laptop's ID.

### Step 4 — Back on the desktop, add the laptop's ID

```bash
./scripts/bootstrap.sh
```

Re-running is safe — the wizard recognizes existing peers and just adds new ones.

```
  Peers already configured on this device: (none yet)
  Add a peer device now? [y/N]: y
  ... [paste laptop ID, name it, mark not-always-on] ...
```

### Step 5 — Watch sync start

Web UI on either device shows green "Connected" indicators. The `claude` folder begins syncing — initial sync of a heavy `~/.claude/` (3–5 GB if you've used Claude Code heavily) takes 15–60 minutes.

---

## 5. Walkthrough: Scenario B

**Setup:** desktop + laptop + dedicated always-on Linux relay (Pi 4/5 with Pi OS, Synology NAS with Syncthing package, mini-PC, or VPS).

### Step 1 — On the relay first (SSH in)

```bash
ssh user@relay-host
git clone https://github.com/iceboerg00/claude-code-syncthing.git
cd claude-code-syncthing
./scripts/bootstrap.sh
```

Skip adding peers (`n`) for now. Copy the **relay's Device ID** from the final output.

### Step 2 — Bootstrap on desktop

Same as Scenario A Step 3, but paste the relay's ID and mark it as **always-on**.

You can also add the laptop's ID at the same time (you'll get it in the next step) — this enables direct sync between desktop and laptop when both are online, falling back to the relay only when one is offline.

### Step 3 — Bootstrap on laptop

Paste the **relay's** ID (always-on=yes). Optionally also the desktop's ID.

### Step 4 — Back on the relay, add desktop + laptop IDs

```bash
ssh user@relay-host
cd claude-code-syncthing
./scripts/bootstrap.sh
```

When prompted, add both. Mark them as not-always-on.

### Step 5 — Verify

To see the relay's Web UI from your desktop without exposing the port:
```bash
ssh -L 8384:127.0.0.1:8384 user@relay-host
# then open http://127.0.0.1:8384 in your browser
```

All three devices should show "Connected" within 60s.

### Storage check

The relay holds full copies of synced folders. Plus trash-can versioning (~2× the live size over 7 days). Verify free space:
```bash
df -h ~
```

---

## 6. Walkthrough: Scenario C

**Setup:** desktop + laptop + Pi 4/5 running Home Assistant OS.

The HAOS Pi is the always-on anchor. **It must be set up first**, because the wizard cannot reach into HAOS — you do it via the HA web UI.

→ Full add-on instructions: [`haos-addon.md`](haos-addon.md)

### Step 1 — On the HAOS Pi (do this FIRST)

1. HA → Settings → Add-ons → Add-on Store → top-right menu → Repositories
2. Add: `https://github.com/Poeschl-HomeAssistant-Addons/repository`
3. Install the **Syncthing** add-on, start it, open the Web UI
4. Note the Pi's Device ID (Actions → Show ID) — **needed on every other device**
5. Create folders in the Pi's Syncthing UI:
   - Folder ID `claude`, path `/share/claude`, ignore patterns from [`../templates/stignore-claude`](../templates/stignore-claude), versioning Trash Can 14 days
   - (Optional) Folder ID matching your `EXTRA_SYNC_LABEL` (default `code`), path `/share/code`, ignore from [`../templates/stignore-extra`](../templates/stignore-extra)

### Step 2 — On the desktop, then the laptop

Run the wizard. When prompted to add a peer, paste the **Pi's Device ID**, mark as always-on. The wizard registers Pi as a Syncthing introducer.

### Step 3 — Back on the HAOS Pi

After each non-Pi device's first sync attempt, the Pi UI shows *"device wants to connect"* notifications — accept each. Folder shares auto-match by ID, no manual folder accept needed.

---

## 7. Verifying your install

### Wizard verification (automatic)

After Phase 5 applies the config, the wizard polls for 30s and reports:
```
  Waiting for peers to come online (up to 30s)...
  ✓ Desktop: connected
  ✓ Pi-HA: connected
```

Or if a peer isn't reachable yet:
```
  ! Desktop: not yet connected (peer must be online and have YOUR ID configured)
```

### Manual checks

**Syncthing process:**
```bash
systemctl --user status syncthing       # Linux
brew services list | grep syncthing     # macOS
Get-Process syncthing                   # Windows
```

**API:**
```bash
curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:8384
# expect: 200
```

**Web UI** at `http://127.0.0.1:8384`:
- Remote Devices panel shows your peers green
- Folders panel shows `claude` (and optional extra) shared with all peers
- Folder summary line says "Up to Date" once initial sync completes

**.stignore is in place:**
```bash
ls -la ~/.claude/.stignore
```

---

## 8. Adding a new device later

Run the bootstrap on the new device, paste any existing peer's Device ID, mark always-on if relevant.

If you set an existing always-on peer as **introducer** during its bootstrap (the wizard does this automatically for `always-on=true` peers), then once the new device connects to the introducer, all other peers known to the introducer get auto-added to the new device's config. You don't have to paste every existing peer's ID.

---

## 9. Optional hardening

### Set a GUI password

Default Syncthing binds to `127.0.0.1:8384` — only local browsers can reach it. For defense-in-depth (especially if you ever expose the port via Tailscale or a reverse proxy):

1. Open `http://127.0.0.1:8384`
2. Actions → Settings → GUI tab
3. Fill **GUI Authentication User** and **Password**
4. Save (Syncthing restarts)

Repeat on each device. The wizard does NOT set this — it's a manual choice per device.

(HAOS doesn't need this — the add-on is exposed only via HA's Ingress, which has its own auth.)

### Force Tailscale-only sync

If all devices are on Tailscale, you can pin Syncthing to use Tailscale IPs only (no relays, no public discovery):

1. In each device's Web UI: Edit Remote Device → Advanced
2. Set **Addresses** to `tcp://<peer-tailscale-ip>:22000`

Now even on hostile networks, sync only goes over your Tailnet.

---

## 10. Common first-run issues

### "Permission denied" running the bootstrap

Linux/macOS:
```bash
chmod +x scripts/bootstrap.sh scripts/link-claude-projects.sh
```

Windows: PowerShell may block unsigned scripts.
```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
# or one-shot:
powershell.exe -ExecutionPolicy Bypass -File .\scripts\bootstrap.ps1
```

### "winget: command not found"

Install **App Installer** from the Microsoft Store.

### Syncthing API returns nothing / `apikey` empty

Means Syncthing started but didn't finish initializing config. Restart it once and re-run:
```bash
systemctl --user restart syncthing && sleep 5
./scripts/bootstrap.sh
```

### `claude --resume` shows no sessions on Linux after sync

The cross-platform symlink trick wasn't applied. The bootstrap runs it automatically when it sees Windows-named folders, but if new ones appeared since:
```bash
./scripts/link-claude-projects.sh
```

### Sync stuck at 99%

The active session jsonl is being written by Claude right now. Close Claude on this device — the percent jumps to 100%. Other devices then pull the final bytes. See [troubleshooting.md](troubleshooting.md).

### "Dropping index entry containing invalid path separator" in the log

A file with a backslash in its name was created on Linux/macOS, and Windows can't represent that. Find and delete on the Linux side:
```bash
find ~/.claude ~/Desktop -name '*\\*' 2>/dev/null
```
Then `rm` what you find. Sync clears up on next rescan.

### Self-paste detection trips

If you accidentally pasted your own Device ID as a peer, the wizard warns and refuses. Re-enter the OTHER device's ID. (Self ID is at the top of Phase 4 output and in your clipboard.)

### Want to start over?

```bash
./scripts/bootstrap.sh --reset    # Linux/macOS
.\scripts\bootstrap.ps1 -Reset    # Windows
```

Removes peer entries, folder shares, and `config.env`. Syncthing stays installed; your `~/.claude/` data is untouched. Re-run the wizard fresh.

---

## What's next

- Day-to-day operations and recovery: [`troubleshooting.md`](troubleshooting.md)
- All flags and env vars: [`cli-reference.md`](cli-reference.md)
- HAOS-specific: [`haos-addon.md`](haos-addon.md)

If you hit something not covered, open an issue.
