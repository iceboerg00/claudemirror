# Installation Guide

Full step-by-step walkthrough for setting up `claude-code-syncthing`. For a one-screen summary see the [README](../README.md). For troubleshooting after install, see [troubleshooting.md](troubleshooting.md).

---

## Table of Contents

1. [Before you start](#1-before-you-start)
2. [Choose your scenario](#2-choose-your-scenario)
3. [Per-platform prerequisites](#3-per-platform-prerequisites)
   - [Linux (Debian/Ubuntu/Pi OS)](#linux-debianubuntupi-os)
   - [Linux (Fedora/Arch)](#linux-fedoraarch)
   - [macOS](#macos)
   - [Windows](#windows)
4. [Walkthrough: Scenario A — Two devices, one always-on](#4-walkthrough-scenario-a)
5. [Walkthrough: Scenario B — Three devices with a dedicated relay](#5-walkthrough-scenario-b)
6. [Walkthrough: Scenario C — HAOS as the relay](#6-walkthrough-scenario-c)
7. [Verifying your install](#7-verifying-your-install)
8. [Adding a new device later](#8-adding-a-new-device-later)
9. [Common first-run issues](#9-common-first-run-issues)

---

## 1. Before you start

### What this installs

- **Syncthing** on each device — the actual sync daemon, ~30 MB
- An **autostart** entry so Syncthing comes up automatically (systemd user service on Linux, `brew services` on macOS, Scheduled Task on Windows)
- A **`.stignore`** file in `~/.claude/` so caches and platform-specific items don't sync
- Optional: same `.stignore` in an additional code/projects directory
- A **`config.env`** in the repo (gitignored) holding the device IDs of your peers

### What this does NOT touch

- Your existing `~/.claude/settings.json` — left exactly as-is. Settings differ between platforms (paths in hooks, statusline scripts), so each device manages its own.
- Your existing `~/.claude/projects/` content — only new data flows in via sync.
- Anything outside `~/.claude/` (and your optional extra folder).

### Decisions to make beforehand

| Decision | Options |
|---|---|
| **Always-on device?** | The desktop you leave running, a NAS, a Pi 4/5, a small VPS, a HAOS instance. Required — see Scenario chooser below. |
| **Extra folder?** | Do you also want to sync code? If yes, pick a path (e.g. `~/Desktop/projekte`, `~/code`). Otherwise leave blank. |
| **GitHub auth?** | The bootstrap doesn't need GitHub. You only need `gh` if you want to clone over HTTPS without entering credentials repeatedly. |

---

## 2. Choose your scenario

```
                                Is at least one of your everyday devices on 24/7?
                                       /                        \
                                     YES                        NO
                                      |                          |
                                      v                          v
                           Scenario A (2 devices)     Need a relay -> Scenario B or C
                                                                      /          \
                                                                 dedicated    HAOS Pi
                                                                 Pi/NAS/VPS     |
                                                                     |          v
                                                                     v       Scenario C
                                                                  Scenario B
```

| Scenario | Devices | Always-on node |
|---|---|---|
| **A** | 2 (desktop + laptop) | the desktop |
| **B** | 3 (desktop + laptop + Pi/NAS/VPS) | the Pi/NAS/VPS |
| **C** | 3 (desktop + laptop + HAOS Pi) | the HAOS Pi |

You can start with A and add a relay later by re-running the bootstrap — peers are appended, not replaced.

---

## 3. Per-platform prerequisites

### Linux (Debian/Ubuntu/Pi OS)

Installed by default on Ubuntu Desktop / Pi OS / WSL: bash, curl, sudo, systemd, python3.

```bash
sudo apt-get update
sudo apt-get install -y curl python3 git
```

The bootstrap will install Syncthing itself from the official APT repository (signed). If you're on a minimal server image, also install:

```bash
sudo apt-get install -y systemd ca-certificates
```

**WSL note:** `systemctl --user` requires `systemd` enabled in WSL. On recent WSL2 with Ubuntu 22.04+ this works out of the box. If you're on WSL1 or older WSL2, Syncthing will still install but won't autostart — you'll need to start it manually with `syncthing --no-browser &`.

### Linux (Fedora/Arch)

The bootstrap auto-detects the package manager. Make sure you have:

```bash
# Fedora
sudo dnf install -y curl python3 git

# Arch
sudo pacman -S curl python git
```

### macOS

You need Homebrew. If you don't have it:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

Then verify the tools the bootstrap uses:

```bash
brew --version
python3 --version
curl --version
```

These are present on a default macOS install after Xcode CLT, plus Homebrew adds Syncthing.

### Windows

Open a regular (non-admin) PowerShell window. Verify:

```powershell
winget --version
$PSVersionTable.PSVersion
```

- **winget** ships with modern Windows 10/11 ("App Installer" from Microsoft Store). If missing, install from the Store.
- **PowerShell 5.1** is the system default and works for the bootstrap. PowerShell 7 also works.
- **Git** is needed to clone the repo: `winget install --id Git.Git -e`

The bootstrap installs Syncthing via winget. No admin rights required — winget installs per-user.

---

## 4. Walkthrough: Scenario A

**Setup:** 1 always-on desktop + 1 mobile laptop.

### Step 1 — Clone the repo on the desktop

```bash
git clone https://github.com/iceboerg00/claude-code-syncthing.git
cd claude-code-syncthing
```

### Step 2 — Run the bootstrap

Linux/macOS:
```bash
./scripts/bootstrap.sh
```
Windows:
```powershell
.\scripts\bootstrap.ps1
```

Sample output:
```
==> Platform: linux
==> Installing Syncthing...
[...apt output...]
==> First run -- creating /home/mike/claude-code-syncthing/config.env
==> Deploying .stignore files...
==> Enabling syncthing.service (systemd --user)...
    Waiting for Syncthing API ok
==> This device ID: ABCDEFG-HIJKLMN-OPQRSTU-VWXYZ12-3456789-ABCDEFG-HIJKLMN-OPQRST7

Current peers in config: 0

Add a peer device now? [y/N]: n
==> Configuring devices...
==> Configuring folders...
    folder claude (POST): HTTP 200

==> Final state:
  Devices:
    - <self>          intro=false auto=false ABCDEFG...
  Folders:
    - claude     path=/home/mike/.claude                  sharedWith=1

==> Done.
    Web UI:        http://127.0.0.1:8384
    Your Device ID: ABCDEFG-HIJKLMN-OPQRSTU-VWXYZ12-3456789-ABCDEFG-HIJKLMN-OPQRST7

    Next: on the other device(s), run this bootstrap and paste
    the Device ID above when prompted.
```

**Copy that Device ID.** You'll need it on the laptop.

### Step 3 — Clone + bootstrap on the laptop

```bash
git clone https://github.com/iceboerg00/claude-code-syncthing.git
cd claude-code-syncthing
./scripts/bootstrap.sh
```

When asked "Add a peer device now? [y/N]" — answer **y**.

```
Add a peer device now? [y/N]: y
Peer device ID (or 'done'): ABCDEFG-HIJKLMN-OPQRSTU-VWXYZ12-3456789-ABCDEFG-HIJKLMN-OPQRST7
Peer name [Peer-1]: Desktop
Is this peer always-on (relay)? [y/N]: y

Peer device ID (or 'done'): done
==> Saved peers to /home/mike/claude-code-syncthing/config.env
==> Configuring devices...
    device Desktop: HTTP 200
==> Configuring folders...
    folder claude (POST): HTTP 200
```

The laptop now knows about the desktop, has shared its `claude` folder with the desktop, and will start syncing as soon as the desktop sees the laptop's device ID.

### Step 4 — Go back to the desktop and add the laptop's ID

The laptop's Device ID was printed at the end of its bootstrap. Copy it.

On the desktop, re-run the bootstrap:
```bash
./scripts/bootstrap.sh
```

```
Add a peer device now? [y/N]: y
Peer device ID (or 'done'): LAPTOPID-XXXXXXX-XXXXXXX-...
Peer name [Peer-1]: Laptop
Is this peer always-on (relay)? [y/N]: n

Peer device ID (or 'done'): done
```

### Step 5 — Watch the sync start

Open Syncthing's web UI at `http://127.0.0.1:8384` on either device. Within 30–60 seconds the other device should appear with a green "Connected" indicator. The `claude` folder begins syncing.

Initial sync of a heavy `~/.claude/` (3–5 GB) takes 15–60 minutes depending on your network. After that, only deltas flow.

---

## 5. Walkthrough: Scenario B

**Setup:** desktop + laptop + dedicated always-on relay (Raspberry Pi 4/5 with Pi OS, Synology NAS with Linux, mini-PC, or VPS).

### Step 1 — Set up the relay first

The relay runs Linux. SSH in:
```bash
ssh user@relay-ip
```

Clone and bootstrap:
```bash
git clone https://github.com/iceboerg00/claude-code-syncthing.git
cd claude-code-syncthing
./scripts/bootstrap.sh
```

Skip adding peers (`n`) for now — you'll add the desktop and laptop after their bootstraps.

**Important:** copy the relay's Device ID from the output. You'll paste this onto every other device.

### Step 2 — Bootstrap on desktop and laptop

Same as Scenario A Step 3, but when adding peers, paste the **relay's** Device ID and mark it as always-on:

```
Add a peer device now? [y/N]: y
Peer device ID (or 'done'): RELAY-ID-...
Peer name [Peer-1]: Relay
Is this peer always-on (relay)? [y/N]: y
```

You can also add the other regular device (desktop adds laptop, laptop adds desktop) so they sync directly when both are online — Syncthing prefers direct connections over routing through the relay.

### Step 3 — Go back to the relay and add desktop + laptop IDs

```bash
ssh user@relay-ip
cd claude-code-syncthing
./scripts/bootstrap.sh
```

Add both, mark them as not always-on (they're regular devices).

### Step 4 — Open Syncthing UIs and verify

On each device, open `http://127.0.0.1:8384` (or `ssh -L 8384:127.0.0.1:8384 user@relay-ip` to tunnel the relay's UI). All three devices should show as connected within a minute.

### Step 5 — Storage check on the relay

The relay will hold a full copy of `~/.claude/` (3–5 GB typical). Make sure there's headroom plus space for trash-can versioning (up to ~2× the live size over time).

```bash
df -h ~
```

If you set `EXTRA_SYNC_DIR` in `config.env` to also sync a code directory, factor in that size too.

---

## 6. Walkthrough: Scenario C

**Setup:** desktop + laptop + a Raspberry Pi 4/5 running Home Assistant OS.

**Order matters here:** the HAOS Pi is the always-on device, so it's the **anchor**. You set it up first, get its Device ID, then the other devices paste that ID as their always-on peer. The bootstrap scripts cannot drive HAOS (no SSH access to the add-on), so the Pi side is UI clicks.

HAOS doesn't let you SSH and `apt install` like normal Linux. You install Syncthing as a **Home Assistant add-on** instead.

→ Full instructions in [`haos-addon.md`](haos-addon.md). The short version:

### Step 1 — On the HAOS Pi (do this FIRST)

1. In HA: Settings → Add-ons → Add-on Store → top-right menu → Repositories → paste `https://github.com/Poeschl-HomeAssistant-Addons/repository`
2. Install the **Syncthing** add-on, start it, open the Web UI
3. Note the Pi's Device ID (Actions → Show ID) — **copy it, you'll need it on every other device**
4. Create two folders in the Pi's Syncthing UI:
   - Folder ID `claude`, path `/share/claude`, ignore patterns from [`../templates/stignore-claude`](../templates/stignore-claude), versioning Trash Can 14 days
   - (Optional) Folder ID matching your `EXTRA_SYNC_LABEL` (default `code`), path `/share/code`, ignore patterns from [`../templates/stignore-extra`](../templates/stignore-extra)

### Step 2 — On the desktop, then the laptop

1. Clone this repo and run the bootstrap (`./scripts/bootstrap.sh` or `.\scripts\bootstrap.ps1`).
2. When prompted "Add a peer device now?" answer **y**.
3. Paste the **Pi's Device ID** (from Step 1.3), name it (e.g. `HA-Pi`), mark **always-on = yes**.

Repeat on the laptop. Each non-Pi device that connects to the Pi gets auto-shared the folders (because both sides match by Folder ID).

### Step 3 — Back on the HAOS Pi

After each non-Pi device boots its Syncthing for the first time, the Pi UI shows a *"device wants to connect"* notification. Accept each. Folder shares auto-match by ID — no manual folder-accept needed.

---

## 7. Verifying your install

Run these checks on each device after bootstrap:

### Syncthing is running

Linux:
```bash
systemctl --user status syncthing
```
Expected: `Active: active (running)`.

macOS:
```bash
brew services list | grep syncthing
```
Expected: `started`.

Windows:
```powershell
Get-Process syncthing
```
Expected: a non-empty result with a PID.

### Web UI is reachable

```bash
curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:8384
```
Expected: `200`.

### Devices are configured

Open `http://127.0.0.1:8384` in a browser. You should see:
- Your peers in the **Remote Devices** panel (right side)
- The `claude` folder in the **Folders** panel (left side), shared with all peers
- Connection state on each peer: ideally green "Connected"

### Sync is making progress

The folder summary line shows "Up to Date" once all peers have the same content. During initial sync it shows transfer progress and ETA.

If a peer is "Disconnected" but you expect it to be online:
- Both devices must be running Syncthing simultaneously for the very first handshake
- Wait 30–60 seconds for discovery to find them
- Check firewalls (TCP/UDP 22000 inbound on the always-on relay if it sits behind NAT)

### `.stignore` is in place

```bash
ls -la ~/.claude/.stignore   # Linux/macOS
```
Should exist and contain the patterns from `templates/stignore-claude`.

---

## 8. Adding a new device later

Run the bootstrap on the new device, paste any existing peer's Device ID, mark always-on if relevant.

If you set an existing always-on peer as **introducer** during its bootstrap (the script does this automatically for `always-on=true` peers), then once the new device connects to the introducer, all the other peers known to the introducer get added to the new device's config automatically. You don't have to manually paste every existing peer's ID on the new device.

To make this work in reverse (existing devices auto-add the new device), re-run the bootstrap on the introducer device and paste the new device's ID there too.

---

## 9. Common first-run issues

### "Permission denied" running the bootstrap

Linux/macOS: the `.sh` script must be executable. After `git clone`:
```bash
chmod +x scripts/bootstrap.sh scripts/link-claude-projects.sh
```

Windows: PowerShell may block unsigned scripts. From an elevated PowerShell:
```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```
Or run with `-ExecutionPolicy Bypass`:
```powershell
powershell.exe -ExecutionPolicy Bypass -File .\scripts\bootstrap.ps1
```

### "winget: command not found" on Windows

Install "App Installer" from the Microsoft Store, or download the latest from <https://github.com/microsoft/winget-cli/releases>.

### Syncthing API returns 401 / config.xml has no apikey

This happens if you started Syncthing once, then ran the bootstrap before the first run had finished initializing. Restart Syncthing once and re-run the bootstrap:
```bash
systemctl --user restart syncthing && sleep 5
./scripts/bootstrap.sh
```

### `claude --resume` shows no sessions on Linux even after sync

This is the cross-platform symlink issue. The bootstrap runs `link-claude-projects.sh` automatically if it sees Windows-named folders. If you skipped that step or sync brought new folders since:
```bash
./scripts/link-claude-projects.sh
```

### Sync stuck at 99%

The active session jsonl is being written by Claude Code right now. Close Claude on this device and the percent jumps to 100%. Other devices then pull the final bytes. See [troubleshooting.md](troubleshooting.md) for other causes.

### Files appear with `.sync-conflict-…` suffixes

Two devices wrote to the same file simultaneously. Recover one version, delete the other. The default Trash-can versioning keeps older copies under `~/.claude/.stversions/` for 7 days. To avoid the issue: only have Claude Code open on one device at a time, and let Syncthing reach green ("Up to Date") before switching.

---

## What's next

- Read [troubleshooting.md](troubleshooting.md) for ongoing operational issues
- For the HAOS-specific setup details, see [haos-addon.md](haos-addon.md)
- The `config.env` is gitignored — back it up separately if you want to redeploy elsewhere with the same peer list

If you hit something not covered here, open an issue on the repo.
