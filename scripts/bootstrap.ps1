# bootstrap.ps1 -- Windows / PowerShell
# Sets up Syncthing-based sync of ~/.claude across devices.
# Re-runnable: each subsequent invocation can add more peers.

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot  = Split-Path -Parent $ScriptDir
$ConfigFile  = Join-Path $RepoRoot "config.env"
$ExampleFile = Join-Path $RepoRoot "config.example.env"

function Info($msg) { Write-Host "==> " -NoNewline -ForegroundColor Cyan; Write-Host $msg }
function Warn($msg) { Write-Host "!!  " -NoNewline -ForegroundColor Yellow; Write-Host $msg }
function Fail($msg) { Write-Host "XX  " -NoNewline -ForegroundColor Red; Write-Host $msg; exit 1 }

function Read-WithDefault($prompt, $default) {
    if ($default) { $reply = Read-Host "$prompt [$default]" }
    else          { $reply = Read-Host $prompt }
    if ([string]::IsNullOrEmpty($reply)) { return $default } else { return $reply }
}

function Confirm-YesNo($prompt) {
    $reply = Read-Host "$prompt [y/N]"
    return $reply -match '^[Yy]$'
}

# ---------- 1. Install Syncthing ----------

Info "Platform: Windows"
if (-not (Get-Command syncthing -ErrorAction SilentlyContinue)) {
    Info "Installing Syncthing via winget..."
    winget install -e --id Syncthing.Syncthing --accept-source-agreements --accept-package-agreements | Out-Null
    $env:Path += ";$env:LOCALAPPDATA\Microsoft\WinGet\Links"
} else {
    Info "Syncthing already installed."
}
$Exe = (Get-Command syncthing -ErrorAction SilentlyContinue).Source
if (-not $Exe) { $Exe = "$env:LOCALAPPDATA\Microsoft\WinGet\Links\syncthing.exe" }

# ---------- 2. Load or create config.env ----------

if (-not (Test-Path $ConfigFile)) {
    Info "First run -- creating $ConfigFile"
    Copy-Item $ExampleFile $ConfigFile
}

function Read-EnvFile($path) {
    $vars = @{}
    foreach ($line in Get-Content $path) {
        if ($line -match '^\s*#') { continue }
        if ($line -match '^\s*$') { continue }
        if ($line -match '^([A-Z_]+)="?(.*?)"?\s*$') {
            $vars[$matches[1]] = $matches[2]
        }
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

# ---------- 3. Deploy stignore ----------

Info "Deploying .stignore files..."
Copy-Item (Join-Path $RepoRoot "templates\stignore-claude") (Join-Path $ClaudeDir ".stignore") -Force
if ($ExtraDir) {
    New-Item -ItemType Directory -Path $ExtraDir -Force | Out-Null
    Copy-Item (Join-Path $RepoRoot "templates\stignore-extra") (Join-Path $ExtraDir ".stignore") -Force
}

# ---------- 4. Autostart ----------

$TaskName = "Syncthing"
if (-not (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue)) {
    Info "Registering Scheduled Task for autostart..."
    $Action    = New-ScheduledTaskAction -Execute $Exe -Argument "--no-browser --no-restart --logfile=`"$env:LOCALAPPDATA\Syncthing\syncthing.log`""
    $Trigger   = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
    $Settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
    $Principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
    Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Settings $Settings -Principal $Principal | Out-Null
}

if (-not (Get-Process syncthing -ErrorAction SilentlyContinue)) {
    Info "Starting Syncthing..."
    Start-Process -FilePath $Exe -ArgumentList "--no-browser","--no-restart" -WindowStyle Hidden
}

Write-Host -NoNewline "    Waiting for API"
for ($i = 0; $i -lt 30; $i++) {
    try {
        Invoke-WebRequest -Uri "http://127.0.0.1:8384" -UseBasicParsing -TimeoutSec 1 | Out-Null
        Write-Host " ok"; break
    } catch { Write-Host -NoNewline "."; Start-Sleep 1 }
}

# ---------- 5. API key + self device ID ----------

$ConfigXml = Join-Path $env:LOCALAPPDATA "Syncthing\config.xml"
$ApiKey    = ([xml](Get-Content $ConfigXml)).configuration.gui.apikey
$Base      = "http://127.0.0.1:8384/rest"
$AuthHdr   = @{ "X-API-Key" = $ApiKey }
$JsonHdr   = @{ "X-API-Key" = $ApiKey; "Content-Type" = "application/json" }
$SelfId    = (Invoke-RestMethod -Uri "$Base/system/status" -Headers $AuthHdr).myID
Info "This device ID: $SelfId"

# ---------- 6. Interactive peer setup ----------

$Ids   = if ($cfg.PEER_IDS)        { $cfg.PEER_IDS.Split(',')        | Where-Object { $_ } } else { @() }
$Names = if ($cfg.PEER_NAMES)      { $cfg.PEER_NAMES.Split(',')      | Where-Object { $_ } } else { @() }
$Alw   = if ($cfg.PEERS_ALWAYS_ON) { $cfg.PEERS_ALWAYS_ON.Split(',') | Where-Object { $_ } } else { @() }

Write-Host ""
Write-Host "Current peers in config: $($Ids.Count)"
for ($i = 0; $i -lt $Ids.Count; $i++) {
    $n = if ($Names[$i]) { $Names[$i] } else { "Peer-$($i+1)" }
    Write-Host "  - $n ($($Ids[$i].Substring(0, [Math]::Min(7,$Ids[$i].Length)))...) always-on=$($Alw[$i])"
}
Write-Host ""

if (Confirm-YesNo "Add a peer device now?") {
    while ($true) {
        $pid = Read-WithDefault "Peer device ID (or 'done')" ""
        if (-not $pid -or $pid -eq "done") { break }
        $pname = Read-WithDefault "Peer name" "Peer-$($Ids.Count + 1)"
        $aon   = if (Confirm-YesNo "Is this peer always-on (relay)?") { "true" } else { "false" }
        $Ids   += $pid
        $Names += $pname
        $Alw   += $aon
        Write-Host ""
    }
    $cfg.PEER_IDS        = $Ids -join ','
    $cfg.PEER_NAMES      = $Names -join ','
    $cfg.PEERS_ALWAYS_ON = $Alw -join ','
    $cfg.CLAUDE_DIR       = $ClaudeDir.Replace('\','/')
    $cfg.EXTRA_SYNC_DIR   = $ExtraDir
    $cfg.EXTRA_SYNC_LABEL = $ExtraLabel
    Write-EnvFile $ConfigFile $cfg
    Info "Saved peers to $ConfigFile"
}

# ---------- 7. Configure devices ----------

$alwaysOnCount = ($Alw | Where-Object { $_ -eq "true" }).Count
if ($alwaysOnCount -eq 0 -and $Ids.Count -gt 0) {
    Warn "No peer is marked always-on. If THIS device isn't always-on either, devices may not sync when offline simultaneously."
}

Info "Configuring devices..."
for ($i = 0; $i -lt $Ids.Count; $i++) {
    $intro = if ($Alw[$i] -eq "true") { $true } else { $false }
    $body = @{
        deviceID = $Ids[$i]; name = $Names[$i]; addresses = @("dynamic")
        compression = "metadata"; introducer = $intro; paused = $false
        autoAcceptFolders = $true; remoteGUIPort = 0
    } | ConvertTo-Json -Compress
    try {
        Invoke-RestMethod -Uri "$Base/config/devices" -Method Post -Headers $JsonHdr -Body $body | Out-Null
        Write-Host "    device $($Names[$i]): added"
    } catch {
        if ($_.Exception.Response.StatusCode.value__ -eq 409) {
            Write-Host "    device $($Names[$i]): already exists"
        } else {
            Write-Host "    device $($Names[$i]): error $($_.Exception.Message)"
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
    Write-Host "    folder $id ($method): ok"
}

Info "Configuring folders..."
Upsert-Folder "claude" $ClaudeDir
if ($ExtraDir) { Upsert-Folder $ExtraLabel $ExtraDir }

# ---------- 8. Final state ----------

Write-Host ""
Info "Final state:"
$conf = Invoke-RestMethod -Uri "$Base/config" -Headers $AuthHdr
Write-Host "  Devices:"
$conf.devices | ForEach-Object { Write-Host "    - $($_.name) intro=$($_.introducer) auto=$($_.autoAcceptFolders) $($_.deviceID.Substring(0,7))..." }
Write-Host "  Folders:"
$conf.folders | ForEach-Object { Write-Host "    - $($_.id) path=$($_.path) sharedWith=$($_.devices.Count)" }

Write-Host ""
Info "Done."
Write-Host "    Web UI:        http://127.0.0.1:8384"
Write-Host "    Your Device ID: $SelfId"
Write-Host ""
Write-Host "    Next: on the other device(s), run the bootstrap and paste"
Write-Host "    the Device ID above when prompted."
