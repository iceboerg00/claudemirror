# bootstrap.ps1 -- guided wizard for Windows / PowerShell
# Sets up Syncthing-based sync of ~/.claude across devices.
# Re-runnable: each invocation can add more peers.
# ASCII-only (works on Windows PowerShell 5.1 default encoding).

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot  = Split-Path -Parent $ScriptDir
$ConfigFile  = Join-Path $RepoRoot "config.env"
$ExampleFile = Join-Path $RepoRoot "config.example.env"
$RepoUrl     = "https://github.com/iceboerg00/claude-code-syncthing.git"

# ---------- presentation helpers ----------

function Phase($n, $total, $title) {
    Write-Host ""
    Write-Host "====================================================================" -ForegroundColor Cyan
    Write-Host "  PHASE $n/$total -- $title" -ForegroundColor Cyan
    Write-Host "====================================================================" -ForegroundColor Cyan
    Write-Host ""
}
function Banner($text) {
    Write-Host ""
    Write-Host "+-------------------------------------------------------------------+" -ForegroundColor Cyan
    Write-Host "|  $text" -ForegroundColor Cyan
    Write-Host "+-------------------------------------------------------------------+" -ForegroundColor Cyan
    Write-Host ""
}
function Box-Command($cmd) {
    $len = $cmd.Length + 4
    $line = "-" * $len
    Write-Host "  +$line+" -ForegroundColor Cyan
    Write-Host "  |  " -NoNewline -ForegroundColor Cyan
    Write-Host $cmd -NoNewline
    Write-Host "  |" -ForegroundColor Cyan
    Write-Host "  +$line+" -ForegroundColor Cyan
}
function Ok($msg)    { Write-Host "  [OK]   " -NoNewline -ForegroundColor Green; Write-Host $msg }
function Note($msg)  { Write-Host "         $msg" -ForegroundColor DarkGray }
function Warn($msg)  { Write-Host "  [WARN] " -NoNewline -ForegroundColor Yellow; Write-Host $msg }
function Fail($msg)  { Write-Host "  [FAIL] " -NoNewline -ForegroundColor Red; Write-Host $msg; exit 1 }

function Pause-Wizard {
    Write-Host ""
    Read-Host "  Press Enter to continue (or Ctrl-C to abort)" | Out-Null
}
function Read-WithDefault($prompt, $default) {
    Write-Host -NoNewline "  "
    if ($default) {
        $reply = Read-Host "$prompt [$default]"
    } else {
        $reply = Read-Host $prompt
    }
    if ([string]::IsNullOrEmpty($reply)) { return $default } else { return $reply }
}
function Confirm-YesNo($prompt) {
    Write-Host -NoNewline "  "
    $reply = Read-Host "$prompt [y/N]"
    return $reply -match '^[Yy]$'
}

# ---------- 1. Welcome ----------

Clear-Host
Write-Host ""
Write-Host "   +-------------------------------------------------------------+" -ForegroundColor Cyan
Write-Host "   |                                                             |" -ForegroundColor Cyan
Write-Host "   |       claude-code-syncthing  --  Setup Wizard               |" -ForegroundColor Cyan
Write-Host "   |                                                             |" -ForegroundColor Cyan
Write-Host "   |   Sync your Claude Code state across multiple devices,      |" -ForegroundColor Cyan
Write-Host "   |   peer-to-peer, no cloud account.                           |" -ForegroundColor Cyan
Write-Host "   |                                                             |" -ForegroundColor Cyan
Write-Host "   +-------------------------------------------------------------+" -ForegroundColor Cyan
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

if (-not (Get-Command syncthing -ErrorAction SilentlyContinue)) {
    Note "Installing Syncthing via winget..."
    winget install -e --id Syncthing.Syncthing --accept-source-agreements --accept-package-agreements | Out-Null
    $env:Path += ";$env:LOCALAPPDATA\Microsoft\WinGet\Links"
    Ok "Syncthing installed"
} else {
    Ok "Syncthing already installed"
}
$Exe = (Get-Command syncthing -ErrorAction SilentlyContinue).Source
if (-not $Exe) { $Exe = "$env:LOCALAPPDATA\Microsoft\WinGet\Links\syncthing.exe" }

# ---------- 3. Local config ----------

Phase 2 4 "Configure this device"

if (-not (Test-Path $ConfigFile)) {
    Copy-Item $ExampleFile $ConfigFile
    Note "Created $ConfigFile (gitignored)"
}

function Read-EnvFile($path) {
    $vars = @{}
    foreach ($line in Get-Content $path) {
        if ($line -match '^\s*#') { continue }
        if ($line -match '^\s*$') { continue }
        if ($line -match '^([A-Z_]+)="?(.*?)"?\s*$') { $vars[$matches[1]] = $matches[2] }
    }
    return $vars
}
function Write-EnvFile($path, $vars) {
    $out = @()
    foreach ($k in @("CLAUDE_DIR","EXTRA_SYNC_DIR","EXTRA_SYNC_LABEL","PEER_IDS","PEER_NAMES","PEERS_ALWAYS_ON")) {
        $v = if ($vars.ContainsKey($k)) { $vars[$k] } else { "" }
        $v = $v -replace '\$HOME', $env:USERPROFILE.Replace('\','/')
        $out += "$k=`"$v`""
    }
    $out | Set-Content -Path $path -Encoding utf8
}

$cfg = Read-EnvFile $ConfigFile
$ClaudeDir = if ($cfg.CLAUDE_DIR) { $cfg.CLAUDE_DIR -replace '\$HOME', $env:USERPROFILE.Replace('\','/') } else { Join-Path $env:USERPROFILE ".claude" }
$ExtraDir   = $cfg.EXTRA_SYNC_DIR
$ExtraLabel = if ($cfg.EXTRA_SYNC_LABEL) { $cfg.EXTRA_SYNC_LABEL } else { "code" }
New-Item -ItemType Directory -Path $ClaudeDir -Force | Out-Null

if (-not $cfg.PEER_IDS -and -not $ExtraDir) {
    Write-Host "  Optional: also sync a code/projects directory between devices."
    Write-Host "  (e.g. ~/Desktop/projekte, ~/code -- leave blank to skip)" -ForegroundColor DarkGray
    while ($true) {
        $ExtraDir = Read-WithDefault "Extra folder path" ""
        if (-not $ExtraDir) { break }
        $ExtraDir = $ExtraDir -replace '^~', $env:USERPROFILE.Replace('\','/')
        if (Test-Path $ExtraDir) {
            Ok "Path exists: $ExtraDir"
            $ExtraLabel = Read-WithDefault "Label for this folder" "code"
            break
        }
        Warn "Path '$ExtraDir' doesn't exist on this device."
        if (Confirm-YesNo "Create it?") {
            New-Item -ItemType Directory -Path $ExtraDir -Force | Out-Null
            Ok "Created $ExtraDir"
            $ExtraLabel = Read-WithDefault "Label for this folder" "code"
            break
        }
        Write-Host "  (typo? press Enter to retry, or type blank to skip extra folder)" -ForegroundColor DarkGray
        $ExtraDir = ""
    }
}

Note "Deploying ignore patterns..."
Copy-Item (Join-Path $RepoRoot "templates\stignore-claude") (Join-Path $ClaudeDir ".stignore") -Force
Ok "$ClaudeDir\.stignore"
if ($ExtraDir) {
    Copy-Item (Join-Path $RepoRoot "templates\stignore-extra") (Join-Path $ExtraDir ".stignore") -Force
    Ok "$ExtraDir\.stignore"
}

$TaskName = "Syncthing"
if (-not (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue)) {
    Note "Setting up Scheduled Task autostart..."
    $Action    = New-ScheduledTaskAction -Execute $Exe -Argument "--no-browser --no-restart --logfile=`"$env:LOCALAPPDATA\Syncthing\syncthing.log`""
    $Trigger   = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
    $Settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
    $Principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
    Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Settings $Settings -Principal $Principal | Out-Null
    Ok "Scheduled Task 'Syncthing' registered"
}
if (-not (Get-Process syncthing -ErrorAction SilentlyContinue)) {
    Note "Starting Syncthing..."
    Start-Process -FilePath $Exe -ArgumentList "--no-browser","--no-restart" -WindowStyle Hidden
    Ok "syncthing started"
}

Write-Host -NoNewline "  Waiting for Syncthing API"
for ($i = 0; $i -lt 30; $i++) {
    try {
        Invoke-WebRequest -Uri "http://127.0.0.1:8384" -UseBasicParsing -TimeoutSec 1 | Out-Null
        Write-Host " ok" -ForegroundColor Green; break
    } catch { Write-Host -NoNewline "."; Start-Sleep 1 }
}

$ConfigXml = Join-Path $env:LOCALAPPDATA "Syncthing\config.xml"
$ApiKey    = ([xml](Get-Content $ConfigXml)).configuration.gui.apikey
$Base      = "http://127.0.0.1:8384/rest"
$AuthHdr   = @{ "X-API-Key" = $ApiKey }
$JsonHdr   = @{ "X-API-Key" = $ApiKey; "Content-Type" = "application/json" }
$SelfId    = (Invoke-RestMethod -Uri "$Base/system/status" -Headers $AuthHdr).myID

# ---------- 4. Pair ----------

Phase 3 4 "Pair with another device"

Write-Host "  Your device ID is:"
Write-Host ""
Write-Host "  $SelfId" -ForegroundColor Green
Write-Host ""
Write-Host "  (You can also see it later: web UI at http://127.0.0.1:8384 -> Actions -> Show ID)" -ForegroundColor DarkGray
Write-Host ""

$Ids   = if ($cfg.PEER_IDS)        { @($cfg.PEER_IDS.Split(',')        | Where-Object { $_ }) } else { @() }
$Names = if ($cfg.PEER_NAMES)      { @($cfg.PEER_NAMES.Split(',')      | Where-Object { $_ }) } else { @() }
$Alw   = if ($cfg.PEERS_ALWAYS_ON) { @($cfg.PEERS_ALWAYS_ON.Split(',') | Where-Object { $_ }) } else { @() }

if ($Ids.Count -gt 0) {
    Write-Host "  Peers already configured on this device:"
    for ($i = 0; $i -lt $Ids.Count; $i++) {
        $marker = ""
        if ($Alw[$i] -eq "true") { $marker = " (always-on)" }
        Write-Host "    * " -NoNewline; Write-Host $Names[$i] -NoNewline
        Write-Host "  $($Ids[$i].Substring(0, [Math]::Min(7,$Ids[$i].Length)))..." -NoNewline -ForegroundColor DarkGray
        if ($marker) { Write-Host $marker -ForegroundColor Yellow } else { Write-Host "" }
    }
    Write-Host ""
}

if (Confirm-YesNo "Add a peer device now?") {

    Banner "Set up the OTHER device, then come back here:"
    Write-Host "  Linux / macOS / Windows -- clone this repo and run the wizard:"
    Box-Command "git clone $RepoUrl"
    Write-Host ""
    Box-Command "cd claude-code-syncthing"
    Write-Host ""
    Write-Host "  On Linux/macOS:" -ForegroundColor DarkGray
    Box-Command "./scripts/bootstrap.sh"
    Write-Host "  On Windows:" -ForegroundColor DarkGray
    Box-Command ".\scripts\bootstrap.ps1"
    Write-Host ""
    Write-Host "  HAOS Pi -- install the Syncthing add-on (UI, no script)." -ForegroundColor DarkGray
    Write-Host "    -> docs/haos-addon.md" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Either way, the other device will SHOW its Device ID:"
    Write-Host "    * wizard prints it at the end"
    Write-Host "    * HAOS UI: Actions -> Show ID"
    Write-Host ""
    Write-Host "  If the other side ASKS for YOUR Device ID, paste this:"
    Write-Host "    $SelfId" -ForegroundColor Green
    Write-Host ""
    Write-Host "  (HAOS doesn't ask -- it auto-accepts whoever connects.)" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Come back here when you have the other device's Device ID."
    Pause-Wizard

    while ($true) {
        $pid = Read-WithDefault "Other device's ID (or 'done')" ""
        if (-not $pid -or $pid -eq "done") { break }
        if ($pid -notmatch '^[A-Z0-9]{7}(-[A-Z0-9]{7}){7}$') {
            Warn "That doesn't look like a Syncthing device ID. Try again, or 'done'."
            continue
        }
        $pname = Read-WithDefault "Name for this peer" "Peer-$($Ids.Count + 1)"
        $aon = if (Confirm-YesNo "Is this peer always-on (a desktop/Pi that stays running)?") { "true" } else { "false" }
        $Ids   += $pid
        $Names += $pname
        $Alw   += $aon
        Ok "Added: $pname ($($pid.Substring(0,7))...) always-on=$aon"
        Write-Host ""
        if (-not (Confirm-YesNo "Add another peer?")) { break }
        Write-Host ""
    }

    $cfg.PEER_IDS        = $Ids -join ','
    $cfg.PEER_NAMES      = $Names -join ','
    $cfg.PEERS_ALWAYS_ON = $Alw -join ','
    $cfg.CLAUDE_DIR       = $ClaudeDir.Replace('\','/')
    $cfg.EXTRA_SYNC_DIR   = $ExtraDir
    $cfg.EXTRA_SYNC_LABEL = $ExtraLabel
    Write-EnvFile $ConfigFile $cfg
    Ok "Config saved to $ConfigFile"
}

# ---------- 5. Apply ----------

Phase 4 4 "Apply Syncthing config"

$alwaysOnCount = ($Alw | Where-Object { $_ -eq "true" }).Count
if ($alwaysOnCount -eq 0 -and $Ids.Count -gt 0) {
    Warn "No peer is marked always-on."
    Warn "Devices may not sync when not simultaneously online."
}

Note "Registering $($Ids.Count) peer device(s)..."
for ($i = 0; $i -lt $Ids.Count; $i++) {
    $intro = if ($Alw[$i] -eq "true") { $true } else { $false }
    $body = @{
        deviceID = $Ids[$i]; name = $Names[$i]; addresses = @("dynamic")
        compression = "metadata"; introducer = $intro; paused = $false
        autoAcceptFolders = $true; remoteGUIPort = 0
    } | ConvertTo-Json -Compress
    try {
        Invoke-RestMethod -Uri "$Base/config/devices" -Method Post -Headers $JsonHdr -Body $body | Out-Null
        Ok "device $($Names[$i]): registered"
    } catch {
        if ($_.Exception.Response.StatusCode.value__ -eq 409) {
            Ok "device $($Names[$i]): already registered"
        } else {
            Warn "device $($Names[$i]): $($_.Exception.Message)"
        }
    }
}

function Upsert-Folder($id, $path) {
    if (-not (Test-Path $path)) { New-Item -ItemType Directory -Path $path -Force | Out-Null }
    $exists = $false
    try { Invoke-RestMethod -Uri "$Base/config/folders/$id" -Headers $AuthHdr -ErrorAction Stop | Out-Null; $exists = $true } catch {}

    $devices = @( @{ deviceID = $SelfId; introducedBy = ""; encryptionPassword = "" } )
    foreach ($pid in $Ids) {
        $devices += @{ deviceID = $pid; introducedBy = ""; encryptionPassword = "" }
    }

    $body = @{
        id = $id; label = $id; path = $path; type = "sendreceive"
        rescanIntervalS = 3600; fsWatcherEnabled = $true; fsWatcherDelayS = 10
        ignorePerms = $false; autoNormalize = $true
        devices = $devices
        versioning = @{
            type = "trashcan"; params = @{ cleanoutDays = "7" }
            cleanupIntervalS = 3600; fsPath = ""; fsType = "basic"
        }
        ignoreDelete = $false; copyOwnershipFromParent = $false
    } | ConvertTo-Json -Depth 10

    $method = if ($exists) { "Put" } else { "Post" }
    $url = if ($exists) { "$Base/config/folders/$id" } else { "$Base/config/folders" }
    Invoke-RestMethod -Uri $url -Method $method -Headers $JsonHdr -Body $body | Out-Null
    Ok "folder $id ($($method.ToLower())): synced with $($Ids.Count) peer(s)"
}

Note "Configuring folders..."
Upsert-Folder "claude" $ClaudeDir
if ($ExtraDir) { Upsert-Folder $ExtraLabel $ExtraDir }

# ---------- 6. Final summary ----------

Write-Host ""
Write-Host "====================================================================" -ForegroundColor Green
Write-Host "  [OK] Setup complete on this device" -ForegroundColor Green
Write-Host "====================================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  This device's ID (share with future peers):"
Write-Host "  $SelfId" -ForegroundColor Green
Write-Host ""
Write-Host "  Web UI:        http://127.0.0.1:8384"
Write-Host "  Config file:   $ConfigFile"
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
        Write-Host $SelfId -ForegroundColor Green
    }
    Write-Host ""
    Write-Host "  Open the web UI to watch -- devices show 'Connected' (green) when paired," -ForegroundColor DarkGray
    Write-Host "  then folders go 'Up to Date' once initial sync finishes (10-60 min for large state)." -ForegroundColor DarkGray
} else {
    Warn "No peers configured yet. Run this wizard again with peer IDs"
    Write-Host "  to enable sync. Until then, Syncthing is installed but not sharing anything."
}

Write-Host ""
Write-Host "  Trouble? See docs/troubleshooting.md" -ForegroundColor DarkGray
Write-Host ""
