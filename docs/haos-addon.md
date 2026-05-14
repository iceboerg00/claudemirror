# Home Assistant OS as an Always-On Relay

If you already run Home Assistant on a Pi 4 / Pi 5 / NUC with HAOS, that machine is a perfect 24/7 Syncthing relay. Storage permitting (a few GB for typical Claude state, more if you sync code), it adds a third sync peer that's always reachable.

> **Start here for Scenario C.** Because HAOS doesn't let the bootstrap script SSH in and install Syncthing, the HAOS Pi has to be set up via the HA web UI **first**. Then desktop and laptop run the regular bootstrap and paste this Pi's Device ID as their always-on peer.

## Prerequisites

- HAOS instance with web UI access
- At least 5–10 GB free under `/share` (typically the SSD on Pi 4/5 with external boot)
- Optional but recommended: HAOS booted from an SSD or NVMe, not an SD card — Claude session jsonls cause heavy write churn

## 1. Add the community add-on repository

1. In Home Assistant: **Settings → Add-ons → Add-on Store**
2. Top-right three-dot menu → **Repositories**
3. Paste this URL and click **Add**:
   ```
   https://github.com/Poeschl-HomeAssistant-Addons/repository
   ```
4. Close, then reload the add-on store.

## 2. Install Syncthing

1. Find **Syncthing** (by Poeschl) in the store and click **INSTALL**.
2. After install completes, click **START**.
3. Optionally enable **Show in sidebar** so you can open Syncthing from HA's left nav.

## 3. Open the Web UI and grab the Device ID

1. Open the add-on's **OPEN WEB UI**.
2. Ignore the yellow "insecure admin access" warning — it's a side-effect of HA's Ingress, not a real exposure ([details](https://github.com/Poeschl/Hassio-Addons/issues/340)).
3. Top right: **Actions → Show ID** — copy the Device ID.

## 4. Create the synced folders

> **Important:** the Folder ID must match what's used on your other peers (the bootstrap scripts use `claude` and `<EXTRA_SYNC_LABEL>`, default `code`).

For each folder you sync from other devices, click **+ Add Folder** and configure:

| Field | claude folder | extra (code) folder |
|---|---|---|
| Folder Label | `claude` | `code` (or your label) |
| Folder ID | `claude` | `code` (or your label) |
| Folder Path | `/share/claude` | `/share/code` |
| File Versioning | Trash Can, 14 days | Trash Can, 14 days |
| Ignore Patterns | Paste from [`../templates/stignore-claude`](../templates/stignore-claude) | Paste from [`../templates/stignore-extra`](../templates/stignore-extra) |
| Sharing | (leave empty for now) | (leave empty for now) |

The 14-day versioning gives you a built-in rolling backup since HAOS storage is usually generous.

## 5. Pair with your other devices

On each of your other devices:
1. Re-run the bootstrap script
2. When prompted "Add a peer device now? [y/N]" answer **y**
3. Paste the Pi Device ID, give it a name (e.g. `Pi-HA`), mark it as **always-on**
4. The bootstrap will register the Pi as an introducer and share both folders with it

Back on the Pi's Syncthing UI you'll see "<device> wants to connect" notifications — accept each. The folder shares should auto-match by ID (no extra clicks needed).

## 6. Watch initial sync

The first time, the Pi pulls the full content of `~/.claude/` from your existing device — typical claude-config size is 2–5 GB if you've used Claude Code heavily. Plan for 15–60 min depending on local network.

## Troubleshooting

**Add-on doesn't appear in store:** make sure you used the new URL (`Poeschl-HomeAssistant-Addons/repository`), not the old `Poeschl/Hassio-Addons` which has been deprecated.

**Folder shows "Out of Sync" forever:** ignore patterns must be identical across all peers. Compare the Ignore Patterns tab on each device.

**Pi runs out of space:** sessions can be heavy. Either reduce versioning days or mount an external drive under `/share` and use a path on that drive when creating the folder.

**SD card wearout warning:** if HAOS boots from SD and you haven't moved data to SSD, that's a real concern. See [HAOS external data disk docs](https://www.home-assistant.io/common-tasks/os/#using-external-data-disk) before syncing GBs of small files.
