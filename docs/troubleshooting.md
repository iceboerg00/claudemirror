# Troubleshooting

For initial setup steps see [installation.md](installation.md). For all CLI flags see [cli-reference.md](cli-reference.md).

## When in doubt: `--reset`

The wizard's nuclear option. Removes peer device entries, folder shares, and `config.env`. **Syncthing stays installed and your `~/.claude/` data is untouched** — only the sync wiring is removed.

```bash
./scripts/bootstrap.sh --reset    # Linux/macOS
.\scripts\bootstrap.ps1 -Reset    # Windows
```

After it finishes, re-run the wizard fresh (`bootstrap.sh` / `bootstrap.ps1`).

Use this when:
- Sync is in some weird state you can't unwind
- You want to test the wizard from scratch without uninstalling Syncthing
- Device IDs changed (re-installed an OS) and you want clean entries

---

## Connection issues

### "Devices show as disconnected in the GUI"

First, **hard-refresh the browser** (Ctrl+Shift+R). The Syncthing GUI sometimes caches connection state.

If still disconnected after refresh:

1. **Verify Syncthing is running on the other device.** Have someone there check:
   ```bash
   systemctl --user status syncthing       # Linux
   brew services list | grep syncthing     # macOS
   Get-Process syncthing                   # Windows
   ```

2. **Check the API for ground truth** (don't trust GUI alone):
   ```bash
   APIKEY=$(grep -oP '(?<=<apikey>)[^<]+' ~/.local/state/syncthing/config.xml | head -1)
   curl -s -H "X-API-Key: $APIKEY" http://127.0.0.1:8384/rest/system/connections | python3 -m json.tool
   ```
   Look for `"connected": true` against the peer's Device ID.

3. **First handshake requires both devices online simultaneously.** After that, devices reconnect automatically when both come online.

4. **Firewall:** Syncthing uses TCP+UDP **22000** for direct connections, UDP **21027** for local discovery. Default Windows Firewall on first run prompts to allow — make sure you said "yes" to private networks.

5. **Same network?** Local discovery only finds devices on the same LAN. For cross-network sync, Syncthing's global discovery + relays handle it (slower) — or install [Tailscale](https://tailscale.com) on both for direct connection.

### "Connected, but folder won't sync past 99%"

Almost always one of:

1. **The active session jsonl is being written.** If you're using Claude Code right now, that session file changes constantly. Syncthing chases it but never catches up. Close Claude on this device — sync hits 100%.

2. **Sync errors.** Click the folder's status indicator in the GUI → look at "Out of Sync Items" or the error count. Common cause: file type mismatch between OSes (Windows vs Linux symlinks). Fix:
   - Add the offending path to `~/.claude/.stignore`
   - In the GUI, click **Override Changes** or **Revert Local Changes** on the failing folder

3. **A peer is offline.** A folder is "100% synced" only when ALL peers have all bytes. If one peer is offline, completion shows the slowest one's progress.

### "Dropping index entry containing invalid path separator" in the log

A file with a backslash (`\`) in its name was created on Linux/macOS, and Windows can't represent backslashes in filenames. Find and delete on the Linux side:

```bash
find ~/.claude ~/Desktop -name '*\\*' 2>/dev/null
```

Then `rm` what you find. Sync will clear up on the next rescan (auto every hour, or click **Rescan** in the GUI).

---

## Cross-platform Claude session resume

### Sessions don't show up on Linux/macOS after sync from Windows

Claude derives `~/.claude/projects/<id>/` from the absolute pwd:
- Windows: `C--Users-Mike-Desktop-myproject`
- Linux:   `-home-mike-Desktop-myproject`

The bootstrap creates symlinks on Linux/macOS (Linux-name → Windows-name) so `claude --resume` finds Windows-originated sessions. If you skipped that step, or new project folders appeared after the first run:

```bash
./scripts/link-claude-projects.sh
```

### Sessions started on Linux don't sync

The `.stignore` in `~/.claude/` excludes `projects/-home-*` and `projects/-Users-*` — those would be the symlinks the bootstrap creates. If a Linux-only Claude session created a real folder under that pattern (not a symlink), it gets ignored too.

Workaround: temporarily edit `~/.claude/.stignore` and remove the relevant exclude line, sync, then restore. Or use Claude on a path that already has a Windows counterpart so the symlink chain works.

This is a known limitation — Claude Code itself doesn't have OS-agnostic project IDs.

---

## Conflict files (`*.sync-conflict-…`)

These appear when two devices wrote to the same file simultaneously. Don't run Claude Code on two devices at once.

### Recovery

1. Compare the conflict file with the original:
   ```bash
   diff ~/.claude/projects/.../<file>.jsonl '~/.claude/projects/.../<file>.sync-conflict-20260514-...jsonl'
   ```
2. Decide which version to keep. Delete the other.
3. The trash-can versioning under `~/.claude/.stversions/` keeps older copies for 7 days if you want to roll back further.

### Prevention

Workflow: close Claude on device A, watch the Syncthing GUI go to "Up to Date" (green), THEN open Claude on device B.

---

## Plugin / skill issues

### Plugin works on Windows but not after sync to Linux

Likely platform-specific binaries (e.g. `.exe`, `.dll`). Re-install the plugin on the Linux side via Claude's plugin command — that fetches the right architecture.

### `skills/<name>` is a symlink that breaks across OSes

The default `.stignore` excludes the most common offenders (`skills/impeccable`, some ui-ux-pro-max paths). For others:

1. Find symlinks in your `~/.claude/`:
   ```bash
   find ~/.claude -type l 2>/dev/null
   ```
2. Add each path to `~/.claude/.stignore`. Syncthing watches the file and re-applies automatically.

---

## Service / install issues

### Syncthing API returns nothing or `apikey` is empty

Means Syncthing started but didn't finish initializing. Restart and re-run:

```bash
# Linux
systemctl --user restart syncthing && sleep 5
./scripts/bootstrap.sh

# Windows
Stop-Process syncthing -Force; Start-Sleep 2
.\scripts\bootstrap.ps1
```

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

### "winget: command not found" on Windows

Install **App Installer** from the Microsoft Store, or grab the latest `.msixbundle` from <https://github.com/microsoft/winget-cli/releases>.

### `systemctl --user` doesn't work (WSL1, minimal containers)

Pre-flight detects this and skips autostart with a warning. Start Syncthing manually:
```bash
syncthing --no-browser >/dev/null 2>&1 &
```

To get autostart: enable systemd in WSL2 (Ubuntu 22.04+ supports it natively), or add the manual command to your shell rc file.

---

## GUI / auth issues

### "Insecure admin access is enabled" yellow warning

- **On Windows / desktop / laptop:** Syncthing GUI binds to `127.0.0.1:8384` only — only local browsers reach it. The warning is conservative; the actual exposure is localhost-only. For defense-in-depth, set a GUI user/password (Actions → Settings → GUI tab).
- **On HAOS:** The add-on is reached via HA's Ingress, which has its own auth. The warning is a known false positive — [details](https://github.com/Poeschl/Hassio-Addons/issues/340).

### Forgot the GUI password

Edit Syncthing's `config.xml`:
```bash
# Linux
nano ~/.local/state/syncthing/config.xml
```
Find `<gui ...>` and remove the `<user>` and `<password>` lines. Restart Syncthing.

---

## Tailscale-specific

### Sync slow even on Tailscale

Syncthing might be using a relay instead of a direct connection. To force Tailscale:

1. In each device's Web UI: Edit Remote Device → Advanced
2. Set **Addresses** to `tcp://<peer-tailscale-ip>:22000`

Find Tailscale IPs with `tailscale status`.

### Devices show two entries in discovery (Tailscale + LAN)

Normal. Syncthing tries both, picks the fastest. No action needed.

---

## How do I uninstall Syncthing entirely?

The wizard's `--reset` only removes the syncing config, not Syncthing itself. To go fully clean:

```bash
# 1. Stop Syncthing
systemctl --user stop syncthing && systemctl --user disable syncthing      # Linux
brew services stop syncthing                                                 # macOS
Stop-Process syncthing -Force; Unregister-ScheduledTask -TaskName Syncthing  # Windows

# 2. Delete config
rm -rf ~/.local/state/syncthing                                              # Linux (newer)
rm -rf ~/.config/syncthing                                                   # Linux (older)
rm -rf "~/Library/Application Support/Syncthing"                             # macOS
Remove-Item -Recurse "$env:LOCALAPPDATA\Syncthing"                           # Windows

# 3. Uninstall package
sudo apt remove syncthing                                                    # Debian/Ubuntu
brew uninstall syncthing                                                     # macOS
winget uninstall Syncthing.Syncthing                                         # Windows

# 4. Remove this repo's local state
rm config.env
```

Your `~/.claude/` content stays untouched.

---

## Still stuck?

- Re-run the wizard with `--reset` then fresh setup
- Check the [installation guide](installation.md) for the correct order of operations
- Inspect `~/.local/state/syncthing/syncthing.log` (Linux) or `%LOCALAPPDATA%\Syncthing\syncthing.log` (Windows) for the real error
- Open an issue with the relevant log lines and what scenario you're running
