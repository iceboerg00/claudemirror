# Troubleshooting

## "I ran the bootstrap but devices aren't connecting"

Check Syncthing's web UI at http://127.0.0.1:8384 on each device:

- **Both peers must accept each other.** When device A adds device B's ID, device B sees a "device wants to connect" notification it must accept. Either accept manually on B's UI, or re-run the bootstrap on B with A's ID — the bootstrap registers peers preemptively which makes acceptance automatic.

- **Discovery may take 30–60s** after starting both Syncthing instances.

- **Firewalls:** Syncthing uses TCP+UDP 22000 for direct connections, UDP 21027 for local discovery. Default Windows Firewall on first run prompts to allow — make sure you said "yes" to private networks at minimum.

## "Initial sync stuck at 99%"

Almost always one of:

1. **The session is actively writing.** If you're using Claude Code right now, the session jsonl is updated continuously. Syncthing chases the file but never quite catches up. This is fine — close Claude briefly and watch it hit 100%.

2. **Sync errors on one device.** Check the folder's status in the UI — if it says "X errors", click to see details. Common cause: a symlink type mismatch between Windows and Linux. Add the offending path to the `.stignore` file in the folder root, then in the UI click **Override Changes** or **Revert Local Changes** on the failing folder.

## "Sessions don't show up on the Linux side after sync"

Claude Code derives the project folder name from the absolute working directory. Windows pwd → `C--Users-Mike-...`, Linux pwd → `-home-mike-...`. The bootstrap script on Linux/macOS runs [`scripts/link-claude-projects.sh`](../scripts/link-claude-projects.sh) which creates symlinks so Linux Claude finds the Windows-named folders.

If you skipped it or sync brought new project folders after bootstrap, just run it again:
```bash
./scripts/link-claude-projects.sh
```

## "Sync conflict files appear (`.sync-conflict-*`)"

This happens when two devices write to the same file at once. Don't run Claude Code on two devices simultaneously. Recovery:
1. Compare the conflict file with the original (`diff`)
2. Keep the version you want
3. Delete the other (or move it aside as a backup)
4. Trash-can versioning preserves older versions in `.stversions/` if you want to go back further

## "How do I add a new device later?"

Run the bootstrap script again on **any** device. When prompted "Add a peer device now? [y/N]" answer **y**, paste the new device's ID, mark always-on if relevant. The peer gets added to that device's Syncthing config. Repeat on each other device. (Or designate one peer as the always-on **introducer** — then peers added to the introducer propagate automatically.)

## "Tailscale + Syncthing — anything special?"

Nothing special is needed. Syncthing's discovery announces all of a device's local IPs, including the Tailscale `100.x.x.x` address. When devices try to connect, Tailscale magically tunnels the traffic. You don't have to configure addresses manually.

If you want to **force** Syncthing to use Tailscale (and never go over the public internet relay): in the Syncthing UI, edit each remote device → **Advanced** → set **Addresses** to `tcp://100.x.x.x:22000` (the peer's Tailscale IP).

## "Can I exclude additional paths from sync?"

Yes. Edit `~/.claude/.stignore` (or the equivalent in your extra folder). The patterns are gitignore-style. Syncthing watches `.stignore` for changes and re-applies it automatically — no restart needed.

## "How do I uninstall?"

1. Stop Syncthing:
   - Linux: `systemctl --user stop syncthing && systemctl --user disable syncthing`
   - Windows: Disable the "Syncthing" Scheduled Task, then `Stop-Process syncthing`
   - macOS: `brew services stop syncthing`
2. Delete config: `rm -rf ~/.local/state/syncthing` (Linux) / `rm -rf "$env:LOCALAPPDATA\Syncthing"` (Windows)
3. Uninstall package: `apt remove syncthing` / `winget uninstall Syncthing.Syncthing` / `brew uninstall syncthing`
4. Remove from this repo: `rm config.env`

Your `~/.claude/` content stays — only the sync mechanism is removed.
