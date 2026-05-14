# demo.ps1 -- non-destructive walkthrough of the wizard UX
# Same banners/prompts/flow as bootstrap.ps1 but installs nothing,
# touches no real Syncthing, writes no files.

$ErrorActionPreference = "Stop"
$RepoUrl = "https://github.com/iceboerg00/claude-code-syncthing.git"
$FakeSelfId = "DEMOSLF-AAAAAAA-BBBBBBB-CCCCCCC-DDDDDDD-EEEEEEE-FFFFFFF-GGGGGG1"

# ---------- presentation helpers (identical to bootstrap.ps1) ----------

function Phase($n, $total, $title) {
    Write-Host ""
    Write-Host "════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "  PHASE $n/$total — $title" -ForegroundColor Cyan
    Write-Host "════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""
}
function Banner($text) {
    Write-Host ""
    Write-Host "┌────────────────────────────────────────────────────────────────────┐" -ForegroundColor Cyan
    Write-Host "│  $text" -ForegroundColor Cyan
    Write-Host "└────────────────────────────────────────────────────────────────────┘" -ForegroundColor Cyan
    Write-Host ""
}
function Box-Command($cmd) {
    $len = $cmd.Length + 4
    $line = "─" * $len
    Write-Host "  ┌$line┐" -ForegroundColor Cyan
    Write-Host "  │  " -NoNewline -ForegroundColor Cyan
    Write-Host $cmd -NoNewline
    Write-Host "  │" -ForegroundColor Cyan
    Write-Host "  └$line┘" -ForegroundColor Cyan
}
function Ok($msg)   { Write-Host "  ✓ " -NoNewline -ForegroundColor Green; Write-Host $msg }
function Note($msg) { Write-Host "  $msg" -ForegroundColor DarkGray }
function Warn($msg) { Write-Host "  ! " -NoNewline -ForegroundColor Yellow; Write-Host $msg }
function Pause-Wizard { Write-Host ""; Read-Host "  Press Enter to continue (or Ctrl-C to abort)" | Out-Null }
function Read-WithDefault($prompt, $default) {
    Write-Host -NoNewline "  "
    if ($default) { $reply = Read-Host "$prompt [$default]" } else { $reply = Read-Host $prompt }
    if ([string]::IsNullOrEmpty($reply)) { return $default } else { return $reply }
}
function Confirm-YesNo($prompt) {
    Write-Host -NoNewline "  "
    $reply = Read-Host "$prompt [y/N]"
    return $reply -match '^[Yy]$'
}
function Fake-Progress($msg) {
    Write-Host -NoNewline "  $msg"
    1..5 | ForEach-Object { Write-Host -NoNewline "."; Start-Sleep -Milliseconds 150 }
    Write-Host " ok" -ForegroundColor Green
}

# ---------- demo banner ----------

Clear-Host
Write-Host ""
Write-Host "   ┌──────────────────────────────────────────────────────────┐" -ForegroundColor Yellow
Write-Host "   │  ⚠  DEMO MODE  —  no real changes are made               │" -ForegroundColor Yellow
Write-Host "   │                                                          │" -ForegroundColor Yellow
Write-Host "   │  This is a UX walkthrough of the real bootstrap wizard.  │" -ForegroundColor Yellow
Write-Host "   │  Nothing is installed, no Syncthing API is called,       │" -ForegroundColor Yellow
Write-Host "   │  no files are written.                                   │" -ForegroundColor Yellow
Write-Host "   └──────────────────────────────────────────────────────────┘" -ForegroundColor Yellow
Start-Sleep -Seconds 1

# ---------- 1. Welcome ----------

Write-Host ""
Write-Host "   ┌─────────────────────────────────────────────────────────────┐" -ForegroundColor Cyan
Write-Host "   │                                                             │" -ForegroundColor Cyan
Write-Host "   │       claude-code-syncthing  —  Setup Wizard                │" -ForegroundColor Cyan
Write-Host "   │                                                             │" -ForegroundColor Cyan
Write-Host "   │   Sync your Claude Code state across multiple devices,      │" -ForegroundColor Cyan
Write-Host "   │   peer-to-peer, no cloud account.                           │" -ForegroundColor Cyan
Write-Host "   │                                                             │" -ForegroundColor Cyan
Write-Host "   └─────────────────────────────────────────────────────────────┘" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Platform detected: Windows  (host: $env:COMPUTERNAME)"
Write-Host ""
Write-Host "  This wizard will:"
Write-Host "    1. Install Syncthing if needed"
Write-Host "    2. Set up autostart so it runs in the background"
Write-Host "    3. Configure ~/.claude as a synced folder (with sane ignores)"
Write-Host "    4. Walk you through pairing with your other device(s)"
Write-Host ""
Write-Host "  Important: at least " -NoNewline; Write-Host "one device must be always-on" -NoNewline -ForegroundColor Yellow
Write-Host " (a desktop you leave"
Write-Host "  running, a Pi, NAS, or HAOS instance). Without it, sync only happens"
Write-Host "  when devices overlap online."
Pause-Wizard

# ---------- 2. Install ----------

Phase 1 4 "Install Syncthing"
Note "Installing Syncthing via winget... [demo: fake]"
Start-Sleep -Milliseconds 500
Ok "Syncthing installed (fake)"

# ---------- 3. Local config ----------

Phase 2 4 "Configure this device"
Note "Created C:\Temp\demo-config.env (gitignored in real run)"
Write-Host ""
Write-Host "  Optional: also sync a code/projects directory between devices."
Write-Host "  (e.g. ~/Desktop/projekte, ~/code -- leave blank to skip)" -ForegroundColor DarkGray
$ExtraDir = Read-WithDefault "Extra folder path" ""
$ExtraLabel = "code"
if ($ExtraDir) { $ExtraLabel = Read-WithDefault "Label for this folder" "code" }

Note "Deploying ignore patterns... [demo: fake]"
Ok "C:\Users\demo\.claude\.stignore"
if ($ExtraDir) { Ok "$ExtraDir\.stignore" }

Note "Setting up Scheduled Task autostart... [demo: fake]"
Ok "Scheduled Task 'Syncthing' registered"
Note "Starting Syncthing... [demo: fake]"
Ok "syncthing started"
Fake-Progress "Waiting for Syncthing API"

# ---------- 4. Pair ----------

Phase 3 4 "Pair with another device"

Write-Host "  Your device ID is:"
Write-Host ""
Write-Host "  $FakeSelfId" -ForegroundColor Green
Write-Host ""
Write-Host "  (You can also see it later: web UI at http://127.0.0.1:8384 -> Actions -> Show ID)" -ForegroundColor DarkGray
Write-Host ""

$Ids   = @()
$Names = @()
$Alw   = @()

if (Confirm-YesNo "Add a peer device now?") {

    Banner "On your OTHER device, run these commands:"
    Box-Command "git clone $RepoUrl"
    Write-Host ""
    Box-Command "cd claude-code-syncthing"
    Write-Host ""
    Write-Host "  On Linux/macOS:" -ForegroundColor DarkGray
    Box-Command "./scripts/bootstrap.sh"
    Write-Host ""
    Write-Host "  On Windows:" -ForegroundColor DarkGray
    Box-Command ".\scripts\bootstrap.ps1"
    Write-Host ""
    Write-Host "  On HAOS see docs/haos-addon.md (UI clicks, no script)." -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  When the other side runs its wizard:"
    Write-Host "    1. It will print " -NoNewline; Write-Host "its" -NoNewline -ForegroundColor White
    Write-Host " device ID. Copy that."
    Write-Host "    2. It will ask for " -NoNewline; Write-Host "your" -NoNewline -ForegroundColor White
    Write-Host " device ID. Paste this one:"
    Write-Host "       $FakeSelfId" -ForegroundColor Green
    Write-Host "    3. Come back here when you have its ID."
    Pause-Wizard

    while ($true) {
        $pid = Read-WithDefault "Other device's ID (or 'done')" ""
        if (-not $pid -or $pid -eq "done") { break }
        if ($pid -notmatch '^[A-Z0-9]{7}(-[A-Z0-9]{7}){7}$') {
            Warn "That doesn't look like a Syncthing device ID. Try again, or 'done'."
            Write-Host "  Demo tip: paste this to continue -> DEMOPER-1111111-2222222-3333333-4444444-5555555-6666666-77777P1" -ForegroundColor DarkGray
            continue
        }
        $pname = Read-WithDefault "Name for this peer" "Peer-$($Ids.Count + 1)"
        $aon = if (Confirm-YesNo "Is this peer always-on (a desktop/Pi that stays running)?") { "true" } else { "false" }
        $Ids   += $pid; $Names += $pname; $Alw += $aon
        Ok "Added: $pname ($($pid.Substring(0,7))...) always-on=$aon"
        Write-Host ""
        if (-not (Confirm-YesNo "Add another peer?")) { break }
        Write-Host ""
    }

    Ok "Config saved to C:\Temp\demo-config.env (fake)"
}

# ---------- 5. Apply ----------

Phase 4 4 "Apply Syncthing config"

$alwaysOnCount = ($Alw | Where-Object { $_ -eq "true" }).Count
if ($alwaysOnCount -eq 0 -and $Ids.Count -gt 0) {
    Warn "No peer is marked always-on."
    Warn "Devices may not sync when not simultaneously online."
}

Note "Registering $($Ids.Count) peer device(s)... [demo: fake API]"
for ($i = 0; $i -lt $Ids.Count; $i++) {
    Start-Sleep -Milliseconds 200
    Ok "device $($Names[$i]): registered"
}

Note "Configuring folders... [demo: fake API]"
Start-Sleep -Milliseconds 300
Ok "folder claude (post): synced with $($Ids.Count) peer(s)"
if ($ExtraDir) {
    Start-Sleep -Milliseconds 300
    Ok "folder $ExtraLabel (post): synced with $($Ids.Count) peer(s)"
}

# ---------- 6. Summary ----------

Write-Host ""
Write-Host "════════════════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "  ✓ Setup complete on this device" -ForegroundColor Green
Write-Host "════════════════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host ""
Write-Host "  This device's ID (share with future peers):"
Write-Host "  $FakeSelfId" -ForegroundColor Green
Write-Host ""
Write-Host "  Web UI:        http://127.0.0.1:8384"
Write-Host "  Config file:   C:\Temp\demo-config.env (fake)"
Write-Host ""

if ($Ids.Count -gt 0) {
    Write-Host "  What happens now:"
    Write-Host "    Sync starts automatically once the other side has YOUR device ID too."
    Write-Host ""
    Write-Host "  On the other device, make sure it knows about you:"
    for ($i = 0; $i -lt $Ids.Count; $i++) {
        Write-Host "    " -NoNewline; Write-Host $Names[$i] -NoNewline
        Write-Host ": re-run the wizard there with " -NoNewline
        Write-Host "y" -NoNewline -ForegroundColor White
        Write-Host " when asked, paste " -NoNewline
        Write-Host $FakeSelfId -ForegroundColor Green
    }
    Write-Host ""
    Write-Host "  Open the web UI to watch — devices show 'Connected' (green) when paired," -ForegroundColor DarkGray
    Write-Host "  then folders go 'Up to Date' once initial sync finishes (10–60 min for large state)." -ForegroundColor DarkGray
} else {
    Warn "No peers configured yet. Run this wizard again with peer IDs"
    Write-Host "  to enable sync. Until then, Syncthing is installed but not sharing anything."
}

Write-Host ""
Write-Host "  Trouble? See docs/troubleshooting.md" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  ⚠ DEMO MODE — none of the above was actually applied." -ForegroundColor Yellow
Write-Host "  To run the real wizard: " -NoNewline -ForegroundColor Yellow
Write-Host ".\scripts\bootstrap.ps1"
Write-Host ""
