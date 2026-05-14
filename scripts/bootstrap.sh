#!/usr/bin/env bash
# bootstrap.sh -- guided wizard for Linux / macOS / WSL / Raspberry Pi OS
# Sets up Syncthing-based sync of ~/.claude across devices.
#
# Usage:
#   ./scripts/bootstrap.sh                -- interactive wizard (default)
#   ./scripts/bootstrap.sh --reset        -- remove peer devices + folder shares + config.env
#   ./scripts/bootstrap.sh --yes          -- non-interactive (read everything from config.env)
#   ./scripts/bootstrap.sh --no-browser   -- don't auto-open Web UI at the end
#   ./scripts/bootstrap.sh --help

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_FILE="$REPO_ROOT/config.env"
EXAMPLE_FILE="$REPO_ROOT/config.example.env"
REPO_URL="https://github.com/iceboerg00/claudemirror.git"

# ---------- arg parsing ----------

RESET_MODE=false
NON_INTERACTIVE=false
NO_BROWSER=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --reset)             RESET_MODE=true; shift ;;
    --yes|-y|--non-interactive) NON_INTERACTIVE=true; shift ;;
    --no-browser)        NO_BROWSER=true; shift ;;
    -h|--help)
      sed -n '2,11p' "$0" | sed 's/^# //'
      exit 0
      ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

# ---------- presentation helpers ----------

if [ -t 1 ]; then BOLD=$'\033[1m'; CYAN=$'\033[1;36m'; GREEN=$'\033[1;32m'; YELLOW=$'\033[1;33m'; RED=$'\033[1;31m'; DIM=$'\033[2m'; RESET=$'\033[0m'
else BOLD=""; CYAN=""; GREEN=""; YELLOW=""; RED=""; DIM=""; RESET=""; fi

phase() { echo; echo "${CYAN}════════════════════════════════════════════════════════════════════${RESET}"; echo "${CYAN}  PHASE ${1}/${2} — ${BOLD}${3}${RESET}"; echo "${CYAN}════════════════════════════════════════════════════════════════════${RESET}"; echo; }
banner() { echo; echo "${CYAN}┌────────────────────────────────────────────────────────────────────┐${RESET}"; echo "${CYAN}│${RESET}  ${BOLD}$1${RESET}"; echo "${CYAN}└────────────────────────────────────────────────────────────────────┘${RESET}"; echo; }
ok()    { echo "  ${GREEN}✓${RESET} $*"; }
note()  { echo "  ${DIM}$*${RESET}"; }
warn()  { echo "  ${YELLOW}!${RESET} $*"; }
fail()  { echo "  ${RED}✗${RESET} $*" >&2; exit 1; }

box_command() {
  local cmd="$1"; local len=${#cmd}; local pad=$((len + 4)); local line
  printf -v line '─%.0s' $(seq 1 $pad)
  echo "  ${CYAN}┌${line}┐${RESET}"
  echo "  ${CYAN}│${RESET}  ${BOLD}${cmd}${RESET}  ${CYAN}│${RESET}"
  echo "  ${CYAN}└${line}┘${RESET}"
}

pause() {
  $NON_INTERACTIVE && return 0
  echo
  read -r -p "  ${BOLD}Press Enter to continue${RESET}${DIM} (or Ctrl-C to abort)${RESET} " _
}
prompt() {
  local q="$1" default="${2:-}" reply
  if $NON_INTERACTIVE; then echo "$default"; return; fi
  if [[ -n "$default" ]]; then read -r -p "  ${BOLD}${q}${RESET} [${default}]: " reply; echo "${reply:-$default}"
  else                          read -r -p "  ${BOLD}${q}${RESET}: " reply;            echo "$reply"; fi
}
confirm() {
  $NON_INTERACTIVE && return 0
  local reply; read -r -p "  ${BOLD}$1${RESET} [y/N]: " reply
  [[ "$reply" =~ ^[Yy]$ ]]
}

# ---------- platform detection + helpers ----------

OS="$(uname -s)"
case "$OS" in
  Linux*)  PLATFORM=linux ;;
  Darwin*) PLATFORM=macos ;;
  *) fail "Unsupported OS: $OS" ;;
esac
HOSTNAME_SHORT="$(hostname -s 2>/dev/null || hostname)"

copy_to_clipboard() {
  local text="$1"
  if command -v pbcopy >/dev/null 2>&1; then echo -n "$text" | pbcopy 2>/dev/null && return 0
  elif command -v xclip >/dev/null 2>&1; then echo -n "$text" | xclip -selection clipboard 2>/dev/null && return 0
  elif command -v xsel >/dev/null 2>&1; then echo -n "$text" | xsel --clipboard --input 2>/dev/null && return 0
  elif command -v wl-copy >/dev/null 2>&1; then echo -n "$text" | wl-copy 2>/dev/null && return 0
  fi
  return 1
}
open_browser() {
  $NO_BROWSER && return 0
  local url="$1"
  if command -v xdg-open >/dev/null 2>&1; then xdg-open "$url" >/dev/null 2>&1 &
  elif command -v open >/dev/null 2>&1; then open "$url" >/dev/null 2>&1
  else return 1; fi
}

# ---------- API helpers (used by main flow + --reset) ----------

find_apikey() {
  for p in \
    "${XDG_STATE_HOME:-$HOME/.local/state}/syncthing/config.xml" \
    "$HOME/.config/syncthing/config.xml" \
    "$HOME/.local/share/syncthing/config.xml" \
    "$HOME/Library/Application Support/Syncthing/config.xml"
  do [[ -f "$p" ]] && { grep -oP '(?<=<apikey>)[^<]+' "$p" | head -1; return; }; done
}

# ---------- --reset path ----------

if $RESET_MODE; then
  echo "${YELLOW}${BOLD}"
  cat <<'EOF'

   ┌───────────────────────────────────────────────────────────┐
   │  RESET MODE                                               │
   │                                                           │
   │  About to remove from this device:                        │
   │   - peer device entries                                   │
   │   - folder shares (claude + extra if any)                 │
   │   - local config.env                                      │
   │                                                           │
   │  Syncthing itself stays installed and running.            │
   │  Your ~/.claude/ data is NOT touched.                     │
   └───────────────────────────────────────────────────────────┘
EOF
  echo "${RESET}"
  if ! confirm "Proceed with reset?"; then echo "Aborted."; exit 0; fi

  APIKEY=$(find_apikey)
  if [[ -z "$APIKEY" ]]; then warn "No Syncthing API key found -- nothing to remove via API."
  else
    BASE="http://127.0.0.1:8384/rest"
    H=(-H "X-API-Key: $APIKEY" -H "Content-Type: application/json")

    # Remove every folder we know about (claude + extra if configured)
    if [[ -f "$CONFIG_FILE" ]]; then
      # shellcheck disable=SC1090
      source "$CONFIG_FILE" 2>/dev/null || true
      EXTRA_SYNC_LABEL="${EXTRA_SYNC_LABEL:-code}"
      for fid in "claude" "$EXTRA_SYNC_LABEL"; do
        code=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE "${H[@]}" "$BASE/config/folders/$fid")
        [[ "$code" == "200" ]] && ok "removed folder: $fid" || note "folder $fid: HTTP $code (probably didn't exist)"
      done
      IFS=',' read -ra _IDS <<<"${PEER_IDS:-}"
      for pid in "${_IDS[@]}"; do
        [[ -z "$pid" ]] && continue
        code=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE "${H[@]}" "$BASE/config/devices/$pid")
        [[ "$code" == "200" ]] && ok "removed peer: ${pid:0:7}…" || note "peer ${pid:0:7}…: HTTP $code"
      done
    else
      note "No config.env found -- skipping API cleanup."
    fi
  fi

  if [[ -f "$CONFIG_FILE" ]]; then rm -f "$CONFIG_FILE"; ok "removed $CONFIG_FILE"; fi

  echo
  echo "${GREEN}${BOLD}  Reset complete.${RESET}"
  echo "  ${DIM}Run ./scripts/bootstrap.sh again to set up fresh.${RESET}"
  exit 0
fi

# ---------- 0. Welcome ----------

clear 2>/dev/null || true
echo "${BOLD}${CYAN}"
cat <<'EOF'

   ┌─────────────────────────────────────────────────────────────┐
   │                                                             │
   │       claudemirror  —  Setup Wizard                │
   │                                                             │
   │   Sync your Claude Code state across multiple devices,      │
   │   peer-to-peer, no cloud account.                           │
   │                                                             │
   └─────────────────────────────────────────────────────────────┘
EOF
echo "${RESET}"
echo "  Platform: ${BOLD}${PLATFORM}${RESET}  host: ${HOSTNAME_SHORT}  $($NON_INTERACTIVE && echo "${DIM}(non-interactive)${RESET}" || true)"
echo
echo "  This wizard will: install Syncthing, set up autostart, configure"
echo "  sync of ~/.claude, and walk you through pairing other devices."
echo
echo "  ${YELLOW}At least one device must be always-on${RESET} (desktop, Pi, NAS, HAOS)."
echo
pause

# ---------- 0a. Pre-flight ----------

phase 1 5 "Pre-flight checks"

PREFLIGHT_FAIL=false
check() { local name="$1"; local cmd="$2"; if eval "$cmd" >/dev/null 2>&1; then ok "$name"; else warn "$name -- not found"; PREFLIGHT_FAIL=true; fi; }

check "curl"     "command -v curl"
check "python3"  "command -v python3"
check "git"      "command -v git"
if [[ "$PLATFORM" == "linux" ]]; then
  if command -v sudo >/dev/null; then ok "sudo"; else warn "sudo not found -- install will fail unless you're root"; PREFLIGHT_FAIL=true; fi
  if systemctl --user --version >/dev/null 2>&1; then ok "systemctl --user"; else warn "systemctl --user not available (WSL1? minimal container?) -- autostart will be skipped"; fi
elif [[ "$PLATFORM" == "macos" ]]; then
  check "brew" "command -v brew"
fi

if $PREFLIGHT_FAIL; then
  warn "Some prerequisites are missing. Install them and re-run, or continue at your own risk."
  confirm "Continue anyway?" || exit 1
fi

# ---------- 1. Install ----------

phase 2 5 "Install Syncthing"

if command -v syncthing >/dev/null 2>&1; then
  ok "Syncthing already installed: $(command -v syncthing)"
else
  note "Installing Syncthing..."
  if [[ "$PLATFORM" == "linux" ]]; then
    if command -v apt-get >/dev/null; then
      sudo mkdir -p /etc/apt/keyrings
      sudo curl -fsSL -o /etc/apt/keyrings/syncthing-archive-keyring.gpg https://syncthing.net/release-key.gpg
      echo "deb [signed-by=/etc/apt/keyrings/syncthing-archive-keyring.gpg] https://apt.syncthing.net/ syncthing stable" | sudo tee /etc/apt/sources.list.d/syncthing.list >/dev/null
      sudo apt-get update -qq
      sudo apt-get install -y syncthing
    elif command -v dnf >/dev/null; then sudo dnf install -y syncthing
    elif command -v pacman >/dev/null; then sudo pacman -S --noconfirm syncthing
    else fail "No supported package manager"; fi
  elif [[ "$PLATFORM" == "macos" ]]; then
    brew install syncthing
  fi
  ok "Syncthing installed"
fi

# ---------- 2. Local config ----------

phase 3 5 "Configure this device"

if [[ ! -f "$CONFIG_FILE" ]]; then cp "$EXAMPLE_FILE" "$CONFIG_FILE"; note "Created $CONFIG_FILE (gitignored)"; fi
# shellcheck disable=SC1090
source "$CONFIG_FILE"
CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
EXTRA_SYNC_DIR="${EXTRA_SYNC_DIR:-}"
EXTRA_SYNC_LABEL="${EXTRA_SYNC_LABEL:-code}"
mkdir -p "$CLAUDE_DIR"

# Notice if user has an existing settings.json
if [[ -f "$CLAUDE_DIR/settings.json" ]]; then
  note "Found existing $CLAUDE_DIR/settings.json -- left alone (settings are per-device)"
fi

if [[ -z "${PEER_IDS:-}" && -z "$EXTRA_SYNC_DIR" ]] && ! $NON_INTERACTIVE; then
  echo "  Optional: also sync a code/projects directory between devices."
  echo "  ${DIM}(e.g. ~/Desktop/projekte, ~/code -- leave blank to skip)${RESET}"
  while true; do
    EXTRA_SYNC_DIR=$(prompt "Extra folder path" "")
    [[ -z "$EXTRA_SYNC_DIR" ]] && break
    EXTRA_SYNC_DIR="${EXTRA_SYNC_DIR/#\~/$HOME}"
    if [[ -d "$EXTRA_SYNC_DIR" ]]; then
      ok "Path exists: $EXTRA_SYNC_DIR"
      EXTRA_SYNC_LABEL=$(prompt "Label for this folder" "code")
      break
    fi
    warn "Path '$EXTRA_SYNC_DIR' doesn't exist on this device."
    if confirm "Create it?"; then
      mkdir -p "$EXTRA_SYNC_DIR"; ok "Created $EXTRA_SYNC_DIR"
      EXTRA_SYNC_LABEL=$(prompt "Label for this folder" "code"); break
    fi
    echo "  ${DIM}(typo? press Enter to retry, or type blank to skip)${RESET}"
    EXTRA_SYNC_DIR=""
  done
fi

note "Deploying ignore patterns..."
cp "$REPO_ROOT/templates/stignore-claude" "$CLAUDE_DIR/.stignore"; ok "$CLAUDE_DIR/.stignore"
[[ -n "$EXTRA_SYNC_DIR" ]] && { cp "$REPO_ROOT/templates/stignore-extra" "$EXTRA_SYNC_DIR/.stignore"; ok "$EXTRA_SYNC_DIR/.stignore"; }

if [[ "$PLATFORM" == "linux" ]] && systemctl --user --version >/dev/null 2>&1; then
  loginctl enable-linger "$USER" 2>/dev/null || true
  systemctl --user enable syncthing.service >/dev/null 2>&1 || true
  systemctl --user restart syncthing.service
  ok "syncthing.service enabled and started"
elif [[ "$PLATFORM" == "macos" ]]; then
  brew services start syncthing >/dev/null
  ok "syncthing started via brew services"
else
  warn "Autostart not set up (systemctl --user unavailable). Start manually: syncthing --no-browser &"
fi

echo -n "  Waiting for Syncthing API"
for i in {1..30}; do
  if curl -s http://127.0.0.1:8384 >/dev/null 2>&1; then echo " ${GREEN}ok${RESET}"; break; fi
  echo -n "."; sleep 1
done

APIKEY=$(find_apikey)
[[ -z "$APIKEY" ]] && fail "Could not locate Syncthing API key"
BASE="http://127.0.0.1:8384/rest"
HDR=(-H "X-API-Key: $APIKEY" -H "Content-Type: application/json")
SELF_ID=$(curl -s "${HDR[@]}" "$BASE/system/status" | python3 -c "import json,sys;print(json.load(sys.stdin)['myID'])")

# ---------- 3. Pair ----------

phase 4 5 "Pair with another device"

echo "${BOLD}  Your device ID is:${RESET}"
echo
echo "  ${GREEN}${BOLD}${SELF_ID}${RESET}"
if copy_to_clipboard "$SELF_ID"; then echo "  ${DIM}(copied to clipboard)${RESET}"
else echo "  ${DIM}(install xclip / wl-clipboard / pbcopy for auto-copy)${RESET}"; fi
echo

IFS=',' read -ra _IDS   <<<"${PEER_IDS:-}"
IFS=',' read -ra _NAMES <<<"${PEER_NAMES:-}"
IFS=',' read -ra _ALW   <<<"${PEERS_ALWAYS_ON:-}"

if [[ -n "${PEER_IDS:-}" ]]; then
  echo "  Peers already configured on this device:"
  for i in "${!_IDS[@]}"; do
    [[ -z "${_IDS[$i]}" ]] && continue
    aon_marker=""; [[ "${_ALW[$i]:-}" == "true" ]] && aon_marker=" ${YELLOW}(always-on)${RESET}"
    echo "    • ${BOLD}${_NAMES[$i]:-Peer-$((i+1))}${RESET}  ${DIM}${_IDS[$i]:0:7}…${RESET}${aon_marker}"
  done
  echo
fi

if confirm "Add a peer device now?"; then

  banner "Set up the OTHER device, then come back here:"
  echo "  ${BOLD}Linux / macOS / Windows${RESET} -- clone this repo and run the wizard:"
  box_command "git clone $REPO_URL && cd claudemirror"
  echo "  ${DIM}then:${RESET}"
  box_command "./scripts/bootstrap.sh           (Linux/macOS)"
  box_command ".\\scripts\\bootstrap.ps1        (Windows)"
  echo
  echo "  ${BOLD}HAOS Pi${RESET} -- install the Syncthing add-on (UI, no script)."
  echo "    ${DIM}-> docs/haos-addon.md${RESET}"
  echo
  echo "  Either way, the other device will ${BOLD}show its Device ID${RESET}."
  echo "  If asked for YOUR ID, paste: ${GREEN}${SELF_ID}${RESET}"
  echo "  ${DIM}(HAOS auto-accepts, no paste needed.)${RESET}"
  echo
  pause

  while true; do
    pid=$(prompt "Other device's ID (or 'done')" "")
    [[ -z "$pid" || "$pid" == "done" ]] && break
    if [[ ! "$pid" =~ ^[A-Z0-9]{7}(-[A-Z0-9]{7}){7}$ ]]; then
      warn "That doesn't look like a Syncthing device ID. Try again, or 'done'."
      continue
    fi
    if [[ "$pid" == "$SELF_ID" ]]; then
      warn "That's THIS device's own ID -- you don't add yourself as a peer."
      continue
    fi
    # Already in the list?
    already=false
    for existing in "${_IDS[@]:-}"; do [[ "$pid" == "$existing" ]] && already=true; done
    if $already; then warn "This peer is already configured. Skipping."; continue; fi
    pname=$(prompt "Name for this peer" "Peer-$((${#_IDS[@]}+1))")
    if confirm "Is this peer always-on (a desktop/Pi that stays running)?"; then aon=true; else aon=false; fi
    _IDS+=("$pid"); _NAMES+=("$pname"); _ALW+=("$aon")
    ok "Added: ${pname} (${pid:0:7}…) always-on=${aon}"
    echo
    confirm "Add another peer?" || break
    echo
  done

  PEER_IDS=$(IFS=,; echo "${_IDS[*]}")
  PEER_NAMES=$(IFS=,; echo "${_NAMES[*]}")
  PEERS_ALWAYS_ON=$(IFS=,; echo "${_ALW[*]}")
  python3 - "$CONFIG_FILE" "$CLAUDE_DIR" "$EXTRA_SYNC_DIR" "$EXTRA_SYNC_LABEL" "$PEER_IDS" "$PEER_NAMES" "$PEERS_ALWAYS_ON" <<'PYEOF'
import sys, pathlib
cfg, claude, extra, extra_label, ids, names, alw = sys.argv[1:]
pathlib.Path(cfg).write_text(f'''CLAUDE_DIR="{claude}"
EXTRA_SYNC_DIR="{extra}"
EXTRA_SYNC_LABEL="{extra_label}"
PEER_IDS="{ids}"
PEER_NAMES="{names}"
PEERS_ALWAYS_ON="{alw}"
''')
PYEOF
  ok "Config saved to $CONFIG_FILE"
fi

# ---------- 4. Apply ----------

phase 5 5 "Apply Syncthing config"

always_on_count=0
for a in "${_ALW[@]:-}"; do [[ "$a" == "true" ]] && always_on_count=$((always_on_count + 1)); done
if [[ "$always_on_count" -eq 0 && "${#_IDS[@]}" -gt 0 ]]; then
  warn "No peer is marked always-on. Sync only happens when devices overlap online."
fi

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

upsert_folder() {
  local id="$1" path="$2"
  local existing; existing=$(curl -s -o /dev/null -w "%{http_code}" "${HDR[@]}" "$BASE/config/folders/$id")
  local method url
  if [[ "$existing" == "200" ]]; then method=PUT; url="$BASE/config/folders/$id"
  else                                  method=POST; url="$BASE/config/folders"; fi
  python3 - "$id" "$path" "$SELF_ID" "${_IDS[@]:-}" <<'PYEOF' > /tmp/folder.json
import json, sys
fid, fpath, self_id, *peer_ids = sys.argv[1:]
peers = [pid for pid in peer_ids if pid]
print(json.dumps({
  "id": fid, "label": fid, "path": fpath, "type": "sendreceive",
  "rescanIntervalS": 3600, "fsWatcherEnabled": True, "fsWatcherDelayS": 10,
  "ignorePerms": False, "autoNormalize": True,
  "devices": [{"deviceID": d, "introducedBy": "", "encryptionPassword": ""} for d in [self_id, *peers]],
  "versioning": {"type": "trashcan", "params": {"cleanoutDays": "7"}, "cleanupIntervalS": 3600, "fsPath": "", "fsType": "basic"},
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

if [[ "$PLATFORM" == "linux" || "$PLATFORM" == "macos" ]]; then
  if [[ -d "$CLAUDE_DIR/projects" ]] && compgen -G "$CLAUDE_DIR/projects/C--*" >/dev/null; then
    note "Creating cross-platform Claude project symlinks..."
    "$REPO_ROOT/scripts/link-claude-projects.sh" "$CLAUDE_DIR/projects" 2>&1 | sed 's/^/    /'
  fi
fi

# ---------- 4a. Verify connections ----------

if [[ "${#_IDS[@]}" -gt 0 ]]; then
  echo
  note "Waiting for peers to come online (up to 30s)..."
  end_t=$(( $(date +%s) + 30 ))
  declare -A seen
  while [[ $(date +%s) -lt $end_t ]]; do
    conns=$(curl -s "${HDR[@]}" "$BASE/system/connections" 2>/dev/null)
    [[ -z "$conns" ]] && { sleep 2; continue; }
    all_seen=true
    for i in "${!_IDS[@]}"; do
      [[ -z "${_IDS[$i]}" ]] && continue
      pid="${_IDS[$i]}"; pname="${_NAMES[$i]}"
      [[ -n "${seen[$pid]:-}" ]] && continue
      connected=$(echo "$conns" | python3 -c "
import json,sys
try:
  c = json.load(sys.stdin)
  print(c['connections'].get('$pid', {}).get('connected', False))
except: print(False)" 2>/dev/null)
      if [[ "$connected" == "True" ]]; then
        ok "${pname}: ${GREEN}connected${RESET}"
        seen[$pid]=1
      else
        all_seen=false
      fi
    done
    $all_seen && break
    sleep 2
  done
  for i in "${!_IDS[@]}"; do
    [[ -z "${_IDS[$i]}" ]] && continue
    pid="${_IDS[$i]}"; pname="${_NAMES[$i]}"
    if [[ -z "${seen[$pid]:-}" ]]; then
      warn "${pname}: not yet connected (${DIM}peer must be online and have YOUR ID configured${RESET})"
    fi
  done
fi

# ---------- 5. Summary ----------

echo
echo "${GREEN}${BOLD}════════════════════════════════════════════════════════════════════${RESET}"
echo "${GREEN}${BOLD}  ✓ Setup complete on this device${RESET}"
echo "${GREEN}${BOLD}════════════════════════════════════════════════════════════════════${RESET}"
echo
echo "  ${BOLD}This device's ID:${RESET}  ${GREEN}${SELF_ID}${RESET}"
copy_to_clipboard "$SELF_ID" >/dev/null && echo "  ${DIM}(also in your clipboard)${RESET}"
echo
echo "  ${BOLD}Web UI:${RESET}        http://127.0.0.1:8384"
echo "  ${BOLD}Config file:${RESET}   $CONFIG_FILE"
echo

if [[ "${#_IDS[@]}" -gt 0 ]]; then
  echo "  ${BOLD}Next:${RESET} make sure each peer device knows YOUR ID."
fi

echo
echo "  ${DIM}Tip: ./scripts/bootstrap.sh --reset to undo. --help for more flags.${RESET}"
echo

if open_browser "http://127.0.0.1:8384"; then
  note "Opening Web UI..."
fi
