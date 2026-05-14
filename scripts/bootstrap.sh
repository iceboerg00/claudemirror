#!/usr/bin/env bash
# bootstrap.sh -- guided wizard for Linux / macOS / WSL / Raspberry Pi OS
# Sets up Syncthing-based sync of ~/.claude across devices.
# Re-runnable: each invocation can add more peers.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_FILE="$REPO_ROOT/config.env"
EXAMPLE_FILE="$REPO_ROOT/config.example.env"
REPO_URL="https://github.com/iceboerg00/claude-code-syncthing.git"

# ---------- presentation helpers ----------

if [ -t 1 ]; then BOLD=$'\033[1m'; CYAN=$'\033[1;36m'; GREEN=$'\033[1;32m'; YELLOW=$'\033[1;33m'; RED=$'\033[1;31m'; DIM=$'\033[2m'; RESET=$'\033[0m'
else BOLD=""; CYAN=""; GREEN=""; YELLOW=""; RED=""; DIM=""; RESET=""; fi

phase() {
  local n="$1" total="$2" title="$3"
  echo
  echo "${CYAN}════════════════════════════════════════════════════════════════════${RESET}"
  echo "${CYAN}  PHASE ${n}/${total} — ${BOLD}${title}${RESET}"
  echo "${CYAN}════════════════════════════════════════════════════════════════════${RESET}"
  echo
}
banner() {
  echo
  echo "${CYAN}┌────────────────────────────────────────────────────────────────────┐${RESET}"
  echo "${CYAN}│${RESET}  ${BOLD}$1${RESET}"
  echo "${CYAN}└────────────────────────────────────────────────────────────────────┘${RESET}"
  echo
}
ok()    { echo "  ${GREEN}✓${RESET} $*"; }
note()  { echo "  ${DIM}$*${RESET}"; }
warn()  { echo "  ${YELLOW}!${RESET} $*"; }
fail()  { echo "  ${RED}✗${RESET} $*" >&2; exit 1; }

box_command() {
  # prints a copy-paste box around a command
  local cmd="$1"
  local len=${#cmd}
  local pad=$((len + 4))
  local line
  printf -v line '─%.0s' $(seq 1 $pad)
  echo "  ${CYAN}┌${line}┐${RESET}"
  echo "  ${CYAN}│${RESET}  ${BOLD}${cmd}${RESET}  ${CYAN}│${RESET}"
  echo "  ${CYAN}└${line}┘${RESET}"
}

pause() {
  echo
  read -r -p "  ${BOLD}Press Enter to continue${RESET}${DIM} (or Ctrl-C to abort)${RESET} " _
}

prompt() {
  local q="$1" default="${2:-}" reply
  if [[ -n "$default" ]]; then
    read -r -p "  ${BOLD}${q}${RESET} [${default}]: " reply
    echo "${reply:-$default}"
  else
    read -r -p "  ${BOLD}${q}${RESET}: " reply
    echo "$reply"
  fi
}
confirm() {
  local reply
  read -r -p "  ${BOLD}$1${RESET} [y/N]: " reply
  [[ "$reply" =~ ^[Yy]$ ]]
}

# ---------- platform detection ----------

OS="$(uname -s)"
case "$OS" in
  Linux*)  PLATFORM=linux ;;
  Darwin*) PLATFORM=macos ;;
  *) fail "Unsupported OS: $OS" ;;
esac
HOSTNAME_SHORT="$(hostname -s 2>/dev/null || hostname)"

# ---------- 1. Welcome ----------

clear 2>/dev/null || true
echo "${BOLD}${CYAN}"
cat <<'EOF'

   ┌─────────────────────────────────────────────────────────────┐
   │                                                             │
   │       claude-code-syncthing  —  Setup Wizard                │
   │                                                             │
   │   Sync your Claude Code state across multiple devices,      │
   │   peer-to-peer, no cloud account.                           │
   │                                                             │
   └─────────────────────────────────────────────────────────────┘
EOF
echo "${RESET}"
echo "  Platform detected: ${BOLD}${PLATFORM}${RESET}  (host: ${HOSTNAME_SHORT})"
echo
echo "  This wizard will:"
echo "    1. Install Syncthing if needed"
echo "    2. Set up autostart so it runs in the background"
echo "    3. Configure ~/.claude as a synced folder (with sane ignores)"
echo "    4. Walk you through pairing with your other device(s)"
echo
echo "  ${YELLOW}Important:${RESET} at least ${BOLD}one device must be always-on${RESET}"
echo "  (a desktop you leave running, a Pi, NAS, or HAOS instance)."
echo "  Without it, sync only happens when devices overlap online."
echo
pause

# ---------- 2. Install ----------

phase 1 4 "Install Syncthing"

if command -v syncthing >/dev/null 2>&1; then
  ok "Syncthing already installed: $(command -v syncthing)"
else
  note "Installing Syncthing..."
  if [[ "$PLATFORM" == "linux" ]]; then
    if command -v apt-get >/dev/null; then
      sudo mkdir -p /etc/apt/keyrings
      sudo curl -fsSL -o /etc/apt/keyrings/syncthing-archive-keyring.gpg \
        https://syncthing.net/release-key.gpg
      echo "deb [signed-by=/etc/apt/keyrings/syncthing-archive-keyring.gpg] https://apt.syncthing.net/ syncthing stable" \
        | sudo tee /etc/apt/sources.list.d/syncthing.list >/dev/null
      sudo apt-get update -qq
      sudo apt-get install -y syncthing
    elif command -v dnf >/dev/null; then sudo dnf install -y syncthing
    elif command -v pacman >/dev/null; then sudo pacman -S --noconfirm syncthing
    else fail "No supported package manager. Install Syncthing manually: https://syncthing.net/downloads/"; fi
  elif [[ "$PLATFORM" == "macos" ]]; then
    if command -v brew >/dev/null; then brew install syncthing
    else fail "Homebrew not found. Install brew first."; fi
  fi
  ok "Syncthing installed"
fi

# ---------- 3. Local config ----------

phase 2 4 "Configure this device"

if [[ ! -f "$CONFIG_FILE" ]]; then
  cp "$EXAMPLE_FILE" "$CONFIG_FILE"
  note "Created $CONFIG_FILE (gitignored)"
fi
# shellcheck disable=SC1090
source "$CONFIG_FILE"
CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
EXTRA_SYNC_DIR="${EXTRA_SYNC_DIR:-}"
EXTRA_SYNC_LABEL="${EXTRA_SYNC_LABEL:-code}"
mkdir -p "$CLAUDE_DIR"

# Optional: prompt for extra sync dir on first run
if [[ -z "${PEER_IDS:-}" && -z "$EXTRA_SYNC_DIR" ]]; then
  echo "  Optional: also sync a code/projects directory between devices."
  echo "  ${DIM}(e.g. ~/Desktop/projekte, ~/code -- leave blank to skip)${RESET}"
  EXTRA_SYNC_DIR=$(prompt "Extra folder path" "")
  if [[ -n "$EXTRA_SYNC_DIR" ]]; then
    EXTRA_SYNC_DIR="${EXTRA_SYNC_DIR/#\~/$HOME}"
    EXTRA_SYNC_LABEL=$(prompt "Label for this folder (used as Syncthing folder ID)" "code")
    mkdir -p "$EXTRA_SYNC_DIR"
  fi
fi

note "Deploying ignore patterns..."
cp "$REPO_ROOT/templates/stignore-claude" "$CLAUDE_DIR/.stignore"
ok "$CLAUDE_DIR/.stignore"
if [[ -n "$EXTRA_SYNC_DIR" ]]; then
  cp "$REPO_ROOT/templates/stignore-extra" "$EXTRA_SYNC_DIR/.stignore"
  ok "$EXTRA_SYNC_DIR/.stignore"
fi

# Autostart + start
if [[ "$PLATFORM" == "linux" ]]; then
  note "Setting up systemd user service..."
  loginctl enable-linger "$USER" 2>/dev/null || true
  systemctl --user enable syncthing.service >/dev/null 2>&1 || true
  systemctl --user restart syncthing.service
  ok "syncthing.service enabled and started"
elif [[ "$PLATFORM" == "macos" ]]; then
  note "Starting via brew services..."
  brew services start syncthing >/dev/null
  ok "syncthing started"
fi

# Wait for API
echo -n "  Waiting for Syncthing API"
for i in {1..30}; do
  if curl -s http://127.0.0.1:8384 >/dev/null 2>&1; then echo " ${GREEN}ok${RESET}"; break; fi
  echo -n "."; sleep 1
done

# API key
find_apikey() {
  for p in \
    "${XDG_STATE_HOME:-$HOME/.local/state}/syncthing/config.xml" \
    "$HOME/.config/syncthing/config.xml" \
    "$HOME/.local/share/syncthing/config.xml" \
    "$HOME/Library/Application Support/Syncthing/config.xml"
  do
    [[ -f "$p" ]] && { grep -oP '(?<=<apikey>)[^<]+' "$p" | head -1; return; }
  done
}
APIKEY=$(find_apikey)
[[ -z "$APIKEY" ]] && fail "Could not locate Syncthing API key"
BASE="http://127.0.0.1:8384/rest"
HDR=(-H "X-API-Key: $APIKEY" -H "Content-Type: application/json")
SELF_ID=$(curl -s "${HDR[@]}" "$BASE/system/status" | python3 -c "import json,sys;print(json.load(sys.stdin)['myID'])")

# ---------- 4. Pair with other devices ----------

phase 3 4 "Pair with another device"

# Show this device's ID prominently
echo "${BOLD}  Your device ID is:${RESET}"
echo
echo "  ${GREEN}${BOLD}${SELF_ID}${RESET}"
echo
echo "  ${DIM}(You can also see it later: web UI at http://127.0.0.1:8384 → Actions → Show ID)${RESET}"
echo

# Parse existing peers
IFS=',' read -ra _IDS   <<<"${PEER_IDS:-}"
IFS=',' read -ra _NAMES <<<"${PEER_NAMES:-}"
IFS=',' read -ra _ALW   <<<"${PEERS_ALWAYS_ON:-}"

# Re-run mode: show what we already know
if [[ -n "${PEER_IDS:-}" ]]; then
  echo "  Peers already configured on this device:"
  for i in "${!_IDS[@]}"; do
    [[ -z "${_IDS[$i]}" ]] && continue
    aon_marker=""; [[ "${_ALW[$i]:-}" == "true" ]] && aon_marker=" ${YELLOW}(always-on)${RESET}"
    echo "    • ${BOLD}${_NAMES[$i]:-Peer-$((i+1))}${RESET}  ${DIM}${_IDS[$i]:0:7}…${RESET}${aon_marker}"
  done
  echo
fi

# Decide: add a peer now?
if confirm "Add a peer device now?"; then

  # Big copy-paste box for the OTHER device
  banner "On your OTHER device, run these commands:"
  if [[ "$PLATFORM" == "linux" || "$PLATFORM" == "macos" ]]; then
    box_command "git clone $REPO_URL && cd claude-code-syncthing && ./scripts/bootstrap.sh"
  fi
  echo "  ${DIM}On Windows the script is ${BOLD}.\\scripts\\bootstrap.ps1${RESET}${DIM}.${RESET}"
  echo "  ${DIM}On HAOS see docs/haos-addon.md (UI clicks, no script).${RESET}"
  echo
  echo "  When the other side runs its wizard:"
  echo "    1. It will print ${BOLD}its${RESET} device ID. Copy that."
  echo "    2. It will ask for ${BOLD}your${RESET} device ID. Paste this one:"
  echo "       ${GREEN}${SELF_ID}${RESET}"
  echo "    3. Come back here when you have its ID."
  echo
  pause

  # Loop: collect one or more peer IDs
  while true; do
    pid=$(prompt "Other device's ID (or 'done')" "")
    [[ -z "$pid" || "$pid" == "done" ]] && break
    # Sanity check: Syncthing IDs are 56 chars in 8 groups of 7 with dashes (63 total)
    if [[ ! "$pid" =~ ^[A-Z0-9]{7}(-[A-Z0-9]{7}){7}$ ]]; then
      warn "That doesn't look like a Syncthing device ID. Try again, or 'done'."
      continue
    fi
    pname=$(prompt "Name for this peer" "Peer-$((${#_IDS[@]}+1))")
    if confirm "Is this peer always-on (a desktop/Pi that stays running)?"; then aon=true; else aon=false; fi
    _IDS+=("$pid"); _NAMES+=("$pname"); _ALW+=("$aon")
    ok "Added: ${pname} (${pid:0:7}…) always-on=${aon}"
    echo
    confirm "Add another peer?" || break
    echo
  done

  # Save config.env
  PEER_IDS=$(IFS=,; echo "${_IDS[*]}")
  PEER_NAMES=$(IFS=,; echo "${_NAMES[*]}")
  PEERS_ALWAYS_ON=$(IFS=,; echo "${_ALW[*]}")
  python3 - "$CONFIG_FILE" "$CLAUDE_DIR" "$EXTRA_SYNC_DIR" "$EXTRA_SYNC_LABEL" \
    "$PEER_IDS" "$PEER_NAMES" "$PEERS_ALWAYS_ON" <<'PYEOF'
import sys, pathlib
cfg, claude, extra, extra_label, ids, names, alw = sys.argv[1:]
pathlib.Path(cfg).write_text(f"""CLAUDE_DIR="{claude}"
EXTRA_SYNC_DIR="{extra}"
EXTRA_SYNC_LABEL="{extra_label}"
PEER_IDS="{ids}"
PEER_NAMES="{names}"
PEERS_ALWAYS_ON="{alw}"
""")
PYEOF
  ok "Config saved to $CONFIG_FILE"
fi

# ---------- 5. Apply config to Syncthing ----------

phase 4 4 "Apply Syncthing config"

# Validate always-on
always_on_count=0
for a in "${_ALW[@]}"; do [[ "$a" == "true" ]] && always_on_count=$((always_on_count + 1)); done
if [[ "$always_on_count" -eq 0 && "${#_IDS[@]}" -gt 0 ]]; then
  warn "No peer is marked always-on."
  warn "Devices may not sync when not simultaneously online."
fi

# Devices
note "Registering ${#_IDS[@]} peer device(s)..."
for i in "${!_IDS[@]}"; do
  [[ -z "${_IDS[$i]}" ]] && continue
  pid="${_IDS[$i]}"; pname="${_NAMES[$i]:-Peer-$((i+1))}"; intro="${_ALW[$i]:-false}"
  body=$(printf '{"deviceID":"%s","name":"%s","addresses":["dynamic"],"compression":"metadata","introducer":%s,"paused":false,"autoAcceptFolders":true,"remoteGUIPort":0}' "$pid" "$pname" "$intro")
  code=$(curl -s -o /dev/null -w "%{http_code}" -X POST "${HDR[@]}" "$BASE/config/devices" -d "$body")
  if [[ "$code" == "200" ]]; then ok "device ${pname}: registered"
  elif [[ "$code" == "409" ]]; then ok "device ${pname}: already registered"
  else warn "device ${pname}: HTTP ${code}"; fi
done

# Folders
upsert_folder() {
  local id="$1" path="$2"
  local existing; existing=$(curl -s -o /dev/null -w "%{http_code}" "${HDR[@]}" "$BASE/config/folders/$id")
  local method url
  if [[ "$existing" == "200" ]]; then method=PUT; url="$BASE/config/folders/$id"
  else                                  method=POST; url="$BASE/config/folders"; fi
  python3 - "$id" "$path" "$SELF_ID" "${_IDS[@]}" <<'PYEOF' > /tmp/folder.json
import json, sys
fid, fpath, self_id, *peer_ids = sys.argv[1:]
peers = [pid for pid in peer_ids if pid]
print(json.dumps({
  "id": fid, "label": fid, "path": fpath, "type": "sendreceive",
  "rescanIntervalS": 3600, "fsWatcherEnabled": True, "fsWatcherDelayS": 10,
  "ignorePerms": False, "autoNormalize": True,
  "devices": [{"deviceID": d, "introducedBy": "", "encryptionPassword": ""}
              for d in [self_id, *peers]],
  "versioning": {"type": "trashcan", "params": {"cleanoutDays": "7"},
                 "cleanupIntervalS": 3600, "fsPath": "", "fsType": "basic"},
  "ignoreDelete": False, "copyOwnershipFromParent": False
}))
PYEOF
  code=$(curl -s -o /dev/null -w "%{http_code}" -X "$method" "${HDR[@]}" "$url" --data @/tmp/folder.json)
  [[ "$code" == "200" ]] && ok "folder ${id} (${method,,}): synced with ${#_IDS[@]} peer(s)" \
                          || warn "folder ${id}: HTTP ${code}"
}

note "Configuring folders..."
upsert_folder "claude" "$CLAUDE_DIR"
[[ -n "$EXTRA_SYNC_DIR" ]] && upsert_folder "$EXTRA_SYNC_LABEL" "$EXTRA_SYNC_DIR"

# Cross-platform symlinks
if [[ "$PLATFORM" == "linux" || "$PLATFORM" == "macos" ]]; then
  if [[ -d "$CLAUDE_DIR/projects" ]] && compgen -G "$CLAUDE_DIR/projects/C--*" >/dev/null; then
    note "Creating cross-platform Claude project symlinks..."
    "$REPO_ROOT/scripts/link-claude-projects.sh" "$CLAUDE_DIR/projects" 2>&1 | sed 's/^/    /'
  fi
fi

# ---------- 6. Final summary ----------

echo
echo "${GREEN}${BOLD}════════════════════════════════════════════════════════════════════${RESET}"
echo "${GREEN}${BOLD}  ✓ Setup complete on this device${RESET}"
echo "${GREEN}${BOLD}════════════════════════════════════════════════════════════════════${RESET}"
echo
echo "  ${BOLD}This device's ID${RESET} (share with future peers):"
echo "  ${GREEN}${SELF_ID}${RESET}"
echo
echo "  ${BOLD}Web UI:${RESET}        http://127.0.0.1:8384"
echo "  ${BOLD}Config file:${RESET}   $CONFIG_FILE"
echo

if [[ "${#_IDS[@]}" -gt 0 ]]; then
  echo "  ${BOLD}What happens now:${RESET}"
  echo "    Sync starts automatically once the other side has YOUR device ID too."
  echo
  echo "  ${BOLD}On the other device, make sure it knows about you:${RESET}"
  for i in "${!_IDS[@]}"; do
    [[ -z "${_IDS[$i]}" ]] && continue
    echo "    ${BOLD}${_NAMES[$i]}${RESET}: re-run the wizard there with ${BOLD}y${RESET} when asked, paste ${GREEN}${SELF_ID}${RESET}"
  done
  echo
  echo "  ${DIM}Open the web UI to watch — devices show 'Connected' (green) when paired,${RESET}"
  echo "  ${DIM}then folders go 'Up to Date' once initial sync finishes (10–60 min for large state).${RESET}"
else
  echo "  ${YELLOW}No peers configured yet.${RESET} Run this wizard again with peer IDs"
  echo "  to enable sync. Until then, Syncthing is installed but not sharing anything."
fi

echo
echo "  ${DIM}Trouble? See docs/troubleshooting.md${RESET}"
echo
