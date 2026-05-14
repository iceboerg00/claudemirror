# bootstrap.ps1 -- guided wizard for Windows / PowerShell
# Sets up Syncthing-based sync of ~/.claude across devices.
#
# Usage:
#   .\scripts\bootstrap.ps1                  -- interactive wizard (default)
#   .\scripts\bootstrap.ps1 -Reset           -- remove peer devices + folder shares + config.env
#   .\scripts\bootstrap.ps1 -Yes             -- non-interactive (read everything from config.env)
#   .\scripts\bootstrap.ps1 -NoBrowser       -- don't auto-open Web UI at the end
#   .\scripts\bootstrap.ps1 -Help

[CmdletBinding()]
param(
    [switch]$Reset,
    [Alias("y","NonInteractive")]
    [switch]$Yes,
    [switch]$NoBrowser,
    [switch]$Help
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot  = Split-Path -Parent $ScriptDir
$ConfigFile  = Join-Path $RepoRoot "config.env"
$ExampleFile = Join-Path $RepoRoot "config.example.env"
$RepoUrl     = "https://github.com/iceboerg00/claudemirror.git"

if ($Help) {
    @"
Usage:
  .\scripts\bootstrap.ps1                  -- interactive wizard (default)
  .\scripts\bootstrap.ps1 -Reset           -- remove peer devices + folder shares + config.env
  .\scripts\bootstrap.ps1 -Yes             -- non-interactive (read everything from config.env)
  .\scripts\bootstrap.ps1 -NoBrowser       -- don't auto-open Web UI at the end
  .\scripts\bootstrap.ps1 -Help            -- this message
"@ | Write-Host
    exit 0
}

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
function Ok($msg)   { Write-Host "  [OK]   " -NoNewline -ForegroundColor Green; Write-Host $msg }
function Note($msg) { Write-Host "         $msg" -ForegroundColor DarkGray }
function Warn($msg) { Write-Host "  [WARN] " -NoNewline -ForegroundColor Yellow; Write-Host $msg }
function Fail($msg) { Write-Host "  [FAIL] " -NoNewline -ForegroundColor Red; Write-Host $msg; exit 1 }

function Pause-Wizard {
    if ($Yes) { return }
    Write-Host ""
    Read-Host "  Press Enter to continue (or Ctrl-C to abort)" | Out-Null
}
function Read-WithDefault($prompt, $default) {
    if ($Yes) { return $default }
    Write-Host -NoNewline "  "
    if ($default) { $reply = Read-Host "$prompt [$default]" } else { $reply = Read-Host $prompt }
    if ([string]::IsNullOrEmpty($reply)) { return $default } else { return $reply }
}
function Confirm-YesNo($prompt) {
    if ($Yes) { return $true }
    Write-Host -NoNewline "  "
    $reply = Read-Host "$prompt [y/N]"
    return $reply -match '^[Yy]$'
}

function Copy-ToClipboard($text) {
    try { Set-Clipboard -Value $text -ErrorAction Stop; return $true } catch { return $false }
}
function Open-Browser($url) {
    if ($NoBrowser) { return $false }
    try { Start-Process $url -ErrorAction Stop; return $true } catch { return $false }
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

function Find-ApiKey {
    $p = Join-Path $env:LOCALAPPDATA "Syncthing\config.xml"
    if (-not (Test-Path $p)) { return $null }
    return ([xml](Get-Content $p)).configuration.gui.apikey
}

# ---------- --reset path ----------

if ($Reset) {
    Write-Host ""
    Write-Host "   +-----------------------------------------------------------+" -ForegroundColor Yellow
    Write-Host "   |  RESET MODE                                               |" -ForegroundColor Yellow
    Write-Host "   |                                                           |" -ForegroundColor Yellow
    Write-Host "   |  About to remove from this device:                        |" -ForegroundColor Yellow
    Write-Host "   |   - peer device entries                                   |" -ForegroundColor Yellow
    Write-Host "   |   - folder shares (claude + extra if any)                 |" -ForegroundColor Yellow
    Write-Host "   |   - local config.env                                      |" -ForegroundColor Yellow
    Write-Host "   |                                                           |" -ForegroundColor Yellow
    Write-Host "   |  Syncthing itself stays installed and running.            |" -ForegroundColor Yellow
    Write-Host "   |  Your ~/.claude/ data is NOT touched.                     |" -ForegroundColor Yellow
    Write-Host "   +-----------------------------------------------------------+" -ForegroundColor Yellow
    Write-Host ""
    if (-not (Confirm-YesNo "Proceed with reset?")) { Write-Host "Aborted."; exit 0 }

    $ApiKey = Find-ApiKey
    if (-not $ApiKey) {
        Warn "No Syncthing API key found -- nothing to remove via API."
    } else {
        $Base    = "http://127.0.0.1:8384/rest"
        $AuthHdr = @{ "X-API-Key" = $ApiKey }

        if (Test-Path $ConfigFile) {
            $cfg = Read-EnvFile $ConfigFile
            $extraLabel = if ($cfg.EXTRA_SYNC_LABEL) { $cfg.EXTRA_SYNC_LABEL } else { "code" }
            foreach ($fid in @("claude", $extraLabel)) {
                try {
                    Invoke-RestMethod -Uri "$Base/config/folders/$fid" -Method Delete -Headers $AuthHdr -ErrorAction Stop | Out-Null
                    Ok "removed folder: $fid"
                } catch {
                    Note "folder ${fid}: probably didn't exist"
                }
            }
            $Ids = if ($cfg.PEER_IDS) { @($cfg.PEER_IDS.Split(',') | Where-Object { $_ }) } else { @() }
            foreach ($peerId in $Ids) {
                try {
                    Invoke-RestMethod -Uri "$Base/config/devices/$peerId" -Method Delete -Headers $AuthHdr -ErrorAction Stop | Out-Null
                    Ok "removed peer: $($peerId.Substring(0,7))..."
                } catch {
                    Note "peer $($peerId.Substring(0,7))...: not found"
                }
            }
        } else {
            Note "No config.env found -- skipping API cleanup."
        }
    }

    if (Test-Path $ConfigFile) { Remove-Item $ConfigFile -Force; Ok "removed $ConfigFile" }

    Write-Host ""
    Write-Host "  Reset complete." -ForegroundColor Green
    Write-Host "  Run .\scripts\bootstrap.ps1 again to set up fresh." -ForegroundColor DarkGray
    exit 0
}

# ---------- 0. Welcome ----------

Clear-Host
Write-Host ""
Write-Host "   +-------------------------------------------------------------+" -ForegroundColor Cyan
Write-Host "   |                                                             |" -ForegroundColor Cyan
Write-Host "   |       claudemirror  --  Setup Wizard               |" -ForegroundColor Cyan
Write-Host "   |                                                             |" -ForegroundColor Cyan
Write-Host "   |   Sync your Claude Code state across multiple devices,      |" -ForegroundColor Cyan
Write-Host "   |   peer-to-peer, no cloud account.                           |" -ForegroundColor Cyan
Write-Host "   |                                                             |" -ForegroundColor Cyan
Write-Host "   +-------------------------------------------------------------+" -ForegroundColor Cyan
Write-Host ""
Write-Host -NoNewline "  Platform: Windows  host: $env:COMPUTERNAME"
if ($Yes) { Write-Host "  (non-interactive)" -ForegroundColor DarkGray } else { Write-Host "" }
Write-Host ""
Write-Host "  This wizard will: install Syncthing, set up autostart, configure"
Write-Host "  sync of ~/.claude, and walk you through pairing other devices."
Write-Host ""
Write-Host "  At least " -NoNewline; Write-Host "one device must be always-on" -NoNewline -ForegroundColor Yellow
Write-Host " (desktop, Pi, NAS, HAOS)."
Pause-Wizard

# ---------- 1. Pre-flight ----------

Phase 1 5 "Pre-flight checks"

$PreflightFail = $false
function Check-Tool($name, $cmd) {
    if (Get-Command $cmd -ErrorAction SilentlyContinue) { Ok $name } else { Warn "$name -- not found"; $script:PreflightFail = $true }
}
Check-Tool "winget" "winget"
Check-Tool "git"    "git"

$psVer = $PSVersionTable.PSVersion
Ok "PowerShell $($psVer.Major).$($psVer.Minor)"

if ($PreflightFail) {
    Warn "Some prerequisites are missing. Install them and re-run, or continue at your own risk."
    if (-not (Confirm-YesNo "Continue anyway?")) { exit 1 }
}

# ---------- 2. Install ----------

Phase 2 5 "Install Syncthing"

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

Phase 3 5 "Configure this device"

if (-not (Test-Path $ConfigFile)) { Copy-Item $ExampleFile $ConfigFile; Note "Created $ConfigFile (gitignored)" }

$cfg = Read-EnvFile $ConfigFile
$ClaudeDir = if ($cfg.CLAUDE_DIR) { $cfg.CLAUDE_DIR -replace '\$HOME', $env:USERPROFILE.Replace('\','/') } else { Join-Path $env:USERPROFILE ".claude" }
$ExtraDir   = $cfg.EXTRA_SYNC_DIR
$ExtraLabel = if ($cfg.EXTRA_SYNC_LABEL) { $cfg.EXTRA_SYNC_LABEL } else { "code" }
New-Item -ItemType Directory -Path $ClaudeDir -Force | Out-Null

if (Test-Path (Join-Path $ClaudeDir "settings.json")) {
    Note "Found existing $ClaudeDir\settings.json -- left alone (settings are per-device)"
}

if (-not $cfg.PEER_IDS -and -not $ExtraDir -and -not $Yes) {
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
        Write-Host "  (typo? press Enter to retry, or type blank to skip)" -ForegroundColor DarkGray
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

$ApiKey  = Find-ApiKey
if (-not $ApiKey) { Fail "Could not locate Syncthing API key" }
$Base    = "http://127.0.0.1:8384/rest"
$AuthHdr = @{ "X-API-Key" = $ApiKey }
$JsonHdr = @{ "X-API-Key" = $ApiKey; "Content-Type" = "application/json" }
$SelfId  = (Invoke-RestMethod -Uri "$Base/system/status" -Headers $AuthHdr).myID

# ---------- 4. Pair ----------

Phase 4 5 "Pair with another device"

Write-Host "  Your device ID is:"
Write-Host ""
Write-Host "  $SelfId" -ForegroundColor Green
if (Copy-ToClipboard $SelfId) { Write-Host "  (copied to clipboard)" -ForegroundColor DarkGray }
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
    Box-Command "cd claudemirror"
    Write-Host ""
    Write-Host "  On Linux/macOS:" -ForegroundColor DarkGray
    Box-Command "./scripts/bootstrap.sh"
    Write-Host "  On Windows:" -ForegroundColor DarkGray
    Box-Command ".\scripts\bootstrap.ps1"
    Write-Host ""
    Write-Host "  HAOS Pi -- install the Syncthing add-on (UI, no script)." -ForegroundColor DarkGray
    Write-Host "    -> docs/haos-addon.md" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Either way, the other device will SHOW its Device ID."
    Write-Host "  If asked for YOUR ID, paste:" -NoNewline; Write-Host " $SelfId" -ForegroundColor Green
    Write-Host "  (HAOS auto-accepts, no paste needed.)" -ForegroundColor DarkGray
    Pause-Wizard

    while ($true) {
        $peerId = Read-WithDefault "Other device's ID (or 'done')" ""
        if (-not $peerId -or $peerId -eq "done") { break }
        if ($peerId -notmatch '^[A-Z0-9]{7}(-[A-Z0-9]{7}){7}$') {
            Warn "That doesn't look like a Syncthing device ID. Try again, or 'done'."
            continue
        }
        if ($peerId -eq $SelfId) {
            Warn "That's THIS device's own ID -- you don't add yourself as a peer."
            continue
        }
        if ($Ids -contains $peerId) {
            Warn "This peer is already configured. Skipping."
            continue
        }
        $pname = Read-WithDefault "Name for this peer" "Peer-$($Ids.Count + 1)"
        $aon = if (Confirm-YesNo "Is this peer always-on (a desktop/Pi that stays running)?") { "true" } else { "false" }
        $Ids   += $peerId
        $Names += $pname
        $Alw   += $aon
        Ok "Added: $pname ($($peerId.Substring(0,7))...) always-on=$aon"
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

Phase 5 5 "Apply Syncthing config"

$alwaysOnCount = ($Alw | Where-Object { $_ -eq "true" }).Count
if ($alwaysOnCount -eq 0 -and $Ids.Count -gt 0) {
    Warn "No peer is marked always-on. Sync only happens when devices overlap online."
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
    foreach ($peerId in $Ids) {
        $devices += @{ deviceID = $peerId; introducedBy = ""; encryptionPassword = "" }
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

# ---------- 5a. Verify connections ----------

if ($Ids.Count -gt 0) {
    Write-Host ""
    Note "Waiting for peers to come online (up to 30s)..."
    $endT = (Get-Date).AddSeconds(30)
    $seen = @{}
    while ((Get-Date) -lt $endT) {
        try {
            $conns = Invoke-RestMethod -Uri "$Base/system/connections" -Headers $AuthHdr -ErrorAction Stop
            $allSeen = $true
            for ($i = 0; $i -lt $Ids.Count; $i++) {
                $peerId = $Ids[$i]
                if ($seen.ContainsKey($peerId)) { continue }
                $c = $conns.connections.$peerId
                if ($c -and $c.connected) {
                    Ok "$($Names[$i]): connected"
                    $seen[$peerId] = $true
                } else { $allSeen = $false }
            }
            if ($allSeen) { break }
        } catch {}
        Start-Sleep -Seconds 2
    }
    for ($i = 0; $i -lt $Ids.Count; $i++) {
        if (-not $seen.ContainsKey($Ids[$i])) {
            Warn "$($Names[$i]): not yet connected (peer must be online and have YOUR ID configured)"
        }
    }
}

# ---------- 6. Summary ----------

Write-Host ""
Write-Host "====================================================================" -ForegroundColor Green
Write-Host "  [OK] Setup complete on this device" -ForegroundColor Green
Write-Host "====================================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  This device's ID:  " -NoNewline; Write-Host $SelfId -ForegroundColor Green
if (Copy-ToClipboard $SelfId) { Write-Host "  (also in your clipboard)" -ForegroundColor DarkGray }
Write-Host ""
Write-Host "  Web UI:        http://127.0.0.1:8384"
Write-Host "  Config file:   $ConfigFile"
Write-Host ""
if ($Ids.Count -gt 0) {
    Write-Host "  Next: make sure each peer device knows YOUR ID."
}
Write-Host ""
Write-Host "  Tip: .\scripts\bootstrap.ps1 -Reset to undo. -Help for more flags." -ForegroundColor DarkGray
Write-Host ""

if (Open-Browser "http://127.0.0.1:8384") { Note "Opening Web UI..." }
