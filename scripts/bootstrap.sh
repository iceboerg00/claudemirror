#!/usr/bin/env bash
# bootstrap.sh -- Linux / macOS / WSL / Raspberry Pi OS
# Sets up Syncthing-based sync of ~/.claude across devices.
# Re-runnable: each subsequent invocation can add more peers.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_FILE="$REPO_ROOT/config.env"
EXAMPLE_FILE="$REPO_ROOT/config.example.env"

# ---------- helpers ----------

color() { printf '\033[%sm%s\033[0m' "$1" "$2"; }
info()  { echo "$(color "1;34" "==>") $*"; }
warn()  { echo "$(color "1;33" "!! ") $*" >&2; }
fail()  { echo "$(color "1;31" "XX ") $*" >&2; exit 1; }

prompt() {
  # usage: prompt "Question" [default]
  local q="$1" default="${2:-}" reply
  if [[ -n "$default" ]]; then
    read -r -p "$q [$default]: " reply
    echo "${reply:-$default}"
  else
    read -r -p "$q: " reply
    echo "$reply"
  fi
}

confirm() {
  # usage: confirm "Question" -> returns 0 (yes) or 1 (no)
  local reply
  read -r -p "$1 [y/N]: " reply
  [[ "$reply" =~ ^[Yy]$ ]]
}

# ---------- 1. Detect platform ----------

OS="$(uname -s)"
case "$OS" in
  Linux*)  PLATFORM=linux ;;
  Darwin*) PLATFORM=macos ;;
  *) fail "Unsupported OS: $OS" ;;
esac
info "Platform: $PLATFORM"

# ---------- 2. Install Syncthing ----------

install_syncthing() {
  if command -v syncthing >/dev/null 2>&1; then
    info "Syncthing already installed: $(command -v syncthing)"
    return
  fi
  info "Installing Syncthing..."
  if [[ "$PLATFORM" == "linux" ]]; then
    if command -v apt-get >/dev/null; then
      sudo mkdir -p /etc/apt/keyrings
      sudo curl -fsSL -o /etc/apt/keyrings/syncthing-archive-keyring.gpg \
        https://syncthing.net/release-key.gpg
      echo "deb [signed-by=/etc/apt/keyrings/syncthing-archive-keyring.gpg] https://apt.syncthing.net/ syncthing stable" \
        | sudo tee /etc/apt/sources.list.d/syncthing.list >/dev/null
      sudo apt-get update -qq
      sudo apt-get install -y syncthing
    elif command -v dnf >/dev/null; then
      sudo dnf install -y syncthing
    elif command -v pacman >/dev/null; then
      sudo pacman -S --noconfirm syncthing
    else
      fail "No supported package manager found. Install Syncthing manually: https://syncthing.net/downloads/"
    fi
  elif [[ "$PLATFORM" == "macos" ]]; then
    if command -v brew >/dev/null; then
      brew install syncthing
    else
      fail "Homebrew not found. Install brew first or download Syncthing manually."
    fi
  fi
}
install_syncthing

# ---------- 3. Load or create config.env ----------

if [[ ! -f "$CONFIG_FILE" ]]; then
  info "First run -- creating $CONFIG_FILE"
  cp "$EXAMPLE_FILE" "$CONFIG_FILE"
fi
# shellcheck disable=SC1090
source "$CONFIG_FILE"

CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
EXTRA_SYNC_DIR="${EXTRA_SYNC_DIR:-}"
EXTRA_SYNC_LABEL="${EXTRA_SYNC_LABEL:-code}"
mkdir -p "$CLAUDE_DIR"

# ---------- 4. Deploy stignore ----------

info "Deploying .stignore files..."
cp "$REPO_ROOT/templates/stignore-claude" "$CLAUDE_DIR/.stignore"
if [[ -n "$EXTRA_SYNC_DIR" ]]; then
  mkdir -p "$EXTRA_SYNC_DIR"
  cp "$REPO_ROOT/templates/stignore-extra" "$EXTRA_SYNC_DIR/.stignore"
fi

# ---------- 5. Autostart + start Syncthing ----------

if [[ "$PLATFORM" == "linux" ]]; then
  info "Enabling syncthing.service (systemd --user)..."
  loginctl enable-linger "$USER" 2>/dev/null || true
  systemctl --user enable syncthing.service >/dev/null 2>&1 || true
  systemctl --user restart syncthing.service
elif [[ "$PLATFORM" == "macos" ]]; then
  info "Starting Syncthing via brew services..."
  brew services start syncthing >/dev/null
fi

# ---------- 6. Wait for API ----------

echo -n "    Waiting for Syncthing API"
for i in {1..30}; do
  if curl -s http://127.0.0.1:8384 >/dev/null 2>&1; then echo " ok"; break; fi
  echo -n "."; sleep 1
done

# ---------- 7. Find API key + self device ID ----------

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
info "This device ID: $SELF_ID"

# ---------- 8. Interactive peer setup ----------

# Parse existing peers from config.env
IFS=',' read -ra _IDS   <<<"${PEER_IDS:-}"
IFS=',' read -ra _NAMES <<<"${PEER_NAMES:-}"
IFS=',' read -ra _ALW   <<<"${PEERS_ALWAYS_ON:-}"

echo
echo "Current peers in config: ${#_IDS[@]}"
for i in "${!_IDS[@]}"; do
  [[ -z "${_IDS[$i]}" ]] && continue
  echo "  - ${_NAMES[$i]:-Peer-$((i+1))}  (${_IDS[$i]:0:7}...)  always-on=${_ALW[$i]:-false}"
done
echo

if confirm "Add a peer device now?"; then
  while true; do
    pid=$(prompt "Peer device ID (or 'done')")
    [[ "$pid" == "done" || -z "$pid" ]] && break
    pname=$(prompt "Peer name" "Peer-$((${#_IDS[@]}+1))")
    if confirm "Is this peer always-on (relay)?"; then aon=true; else aon=false; fi
    _IDS+=("$pid")
    _NAMES+=("$pname")
    _ALW+=("$aon")
    echo
  done

  # Save back to config.env
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
  info "Saved peers to $CONFIG_FILE"
fi

# ---------- 9. Configure Syncthing via API ----------

# Validate: at least one always-on among the peers OR this device is always-on
always_on_count=0
for a in "${_ALW[@]}"; do [[ "$a" == "true" ]] && always_on_count=$((always_on_count + 1)); done
if [[ "$always_on_count" -eq 0 && "${#_IDS[@]}" -gt 0 ]]; then
  warn "No peer is marked always-on. If THIS device is not always-on either, devices may not sync when they aren't simultaneously online."
fi

info "Configuring devices..."
for i in "${!_IDS[@]}"; do
  [[ -z "${_IDS[$i]}" ]] && continue
  pid="${_IDS[$i]}"
  pname="${_NAMES[$i]:-Peer-$((i+1))}"
  introducer="${_ALW[$i]:-false}"  # always-on peers become introducers
  body=$(printf '{"deviceID":"%s","name":"%s","addresses":["dynamic"],"compression":"metadata","introducer":%s,"paused":false,"autoAcceptFolders":true,"remoteGUIPort":0}' \
    "$pid" "$pname" "$introducer")
  code=$(curl -s -o /dev/null -w "%{http_code}" -X POST "${HDR[@]}" "$BASE/config/devices" -d "$body")
  echo "    device $pname: HTTP $code"
done

upsert_folder() {
  local id="$1" path="$2"
  local existing
  existing=$(curl -s -o /dev/null -w "%{http_code}" "${HDR[@]}" "$BASE/config/folders/$id")
  local method url
  if [[ "$existing" == "200" ]]; then method=PUT; url="$BASE/config/folders/$id"
  else                                  method=POST; url="$BASE/config/folders"
  fi
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
  echo "    folder $id ($method): HTTP $code"
}

info "Configuring folders..."
upsert_folder "claude" "$CLAUDE_DIR"
if [[ -n "$EXTRA_SYNC_DIR" ]]; then
  upsert_folder "$EXTRA_SYNC_LABEL" "$EXTRA_SYNC_DIR"
fi

# ---------- 10. Cross-platform project-folder symlinks ----------

if [[ "$PLATFORM" == "linux" || "$PLATFORM" == "macos" ]]; then
  if [[ -d "$CLAUDE_DIR/projects" ]] && compgen -G "$CLAUDE_DIR/projects/C--*" >/dev/null; then
    info "Creating cross-platform Claude project symlinks..."
    "$REPO_ROOT/scripts/link-claude-projects.sh" || true
  fi
fi

# ---------- 11. Print final state ----------

echo
info "Final state:"
curl -s "${HDR[@]}" "$BASE/config" | python3 <<'PYEOF'
import json, sys
c = json.load(sys.stdin)
print("  Devices:")
for d in c["devices"]:
    print(f"    - {d['name']:<14} intro={d['introducer']!s:<5} auto={d['autoAcceptFolders']!s:<5} {d['deviceID'][:7]}...")
print("  Folders:")
for f in c["folders"]:
    print(f"    - {f['id']:<10} path={f['path']:<40} sharedWith={len(f['devices'])}")
PYEOF

echo
info "Done."
echo "    Web UI:        http://127.0.0.1:8384"
echo "    Your Device ID: $SELF_ID"
echo
echo "    Next: on the other device(s), run this bootstrap and paste"
echo "    the Device ID above when prompted."
