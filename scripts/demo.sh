#!/usr/bin/env bash
# demo.sh -- non-destructive walkthrough of the wizard UX
# Same banners/prompts/flow as bootstrap.sh but installs nothing,
# touches no real Syncthing, writes no files outside /tmp.
# Use this to preview what the real bootstrap looks like.

set -u

REPO_URL="https://github.com/iceboerg00/claude-code-syncthing.git"

# fake values
FAKE_SELF_ID="DEMOSLF-AAAAAAA-BBBBBBB-CCCCCCC-DDDDDDD-EEEEEEE-FFFFFFF-GGGGGG1"
FAKE_PLATFORM="linux"
FAKE_HOST="demo-host"

# ---------- presentation helpers (identical to bootstrap.sh) ----------

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

box_command() {
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
  if [[ -n "$default" ]]; then read -r -p "  ${BOLD}${q}${RESET} [${default}]: " reply; echo "${reply:-$default}"
  else                          read -r -p "  ${BOLD}${q}${RESET}: " reply;            echo "$reply"; fi
}
confirm() {
  local reply
  read -r -p "  ${BOLD}$1${RESET} [y/N]: " reply
  [[ "$reply" =~ ^[Yy]$ ]]
}
fake_progress() {
  echo -n "  $1"
  for _ in 1 2 3 4 5; do echo -n "."; sleep 0.15; done
  echo " ${GREEN}ok${RESET}"
}

# ---------- demo banner ----------

clear 2>/dev/null || true
echo "${YELLOW}${BOLD}"
cat <<'EOF'

   ┌──────────────────────────────────────────────────────────┐
   │  ⚠  DEMO MODE  —  no real changes are made               │
   │                                                          │
   │  This is a UX walkthrough of the real bootstrap wizard.  │
   │  Nothing is installed, no Syncthing API is called,       │
   │  no files are written outside /tmp.                      │
   └──────────────────────────────────────────────────────────┘
EOF
echo "${RESET}"
sleep 1

# ---------- 1. Welcome ----------

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
echo "  Platform detected: ${BOLD}${FAKE_PLATFORM}${RESET}  (host: ${FAKE_HOST})"
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
note "Installing Syncthing... ${DIM}[demo: fake apt-get]${RESET}"
sleep 0.5
ok "Syncthing installed (fake)"

# ---------- 3. Local config ----------

phase 2 4 "Configure this device"

note "Created /tmp/demo-config.env ${DIM}(gitignored in real run)${RESET}"
echo
echo "  Optional: also sync a code/projects directory between devices."
echo "  ${DIM}(e.g. ~/Desktop/projekte, ~/code -- leave blank to skip)${RESET}"
extra_dir=$(prompt "Extra folder path" "")
extra_label="code"
if [[ -n "$extra_dir" ]]; then
  extra_label=$(prompt "Label for this folder" "code")
fi

note "Deploying ignore patterns... ${DIM}[demo: fake]${RESET}"
ok "/home/demo/.claude/.stignore"
[[ -n "$extra_dir" ]] && ok "$extra_dir/.stignore"

note "Setting up systemd user service... ${DIM}[demo: fake]${RESET}"
ok "syncthing.service enabled and started"

fake_progress "Waiting for Syncthing API"

# ---------- 4. Pair ----------

phase 3 4 "Pair with another device"

echo "${BOLD}  Your device ID is:${RESET}"
echo
echo "  ${GREEN}${BOLD}${FAKE_SELF_ID}${RESET}"
echo
echo "  ${DIM}(You can also see it later: web UI at http://127.0.0.1:8384 → Actions → Show ID)${RESET}"
echo

declare -a _IDS _NAMES _ALW

if confirm "Add a peer device now?"; then

  banner "On your OTHER device, run these commands:"
  box_command "git clone $REPO_URL && cd claude-code-syncthing && ./scripts/bootstrap.sh"
  echo "  ${DIM}On Windows the script is ${BOLD}.\\scripts\\bootstrap.ps1${RESET}${DIM}.${RESET}"
  echo "  ${DIM}On HAOS see docs/haos-addon.md (UI clicks, no script).${RESET}"
  echo
  echo "  When the other side runs its wizard:"
  echo "    1. It will print ${BOLD}its${RESET} device ID. Copy that."
  echo "    2. It will ask for ${BOLD}your${RESET} device ID. Paste this one:"
  echo "       ${GREEN}${FAKE_SELF_ID}${RESET}"
  echo "    3. Come back here when you have its ID."
  echo
  pause

  while true; do
    pid=$(prompt "Other device's ID (or 'done')" "")
    [[ -z "$pid" || "$pid" == "done" ]] && break
    if [[ ! "$pid" =~ ^[A-Z0-9]{7}(-[A-Z0-9]{7}){7}$ ]]; then
      warn "That doesn't look like a Syncthing device ID. Try again, or 'done'."
      echo "  ${DIM}Demo tip: paste this to continue → DEMOPER-1111111-2222222-3333333-4444444-5555555-6666666-77777P1${RESET}"
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

  ok "Config saved to /tmp/demo-config.env ${DIM}(fake)${RESET}"
fi

# ---------- 5. Apply ----------

phase 4 4 "Apply Syncthing config"

always_on_count=0
for a in "${_ALW[@]:-}"; do [[ "$a" == "true" ]] && always_on_count=$((always_on_count + 1)); done
if [[ "$always_on_count" -eq 0 && "${#_IDS[@]}" -gt 0 ]]; then
  warn "No peer is marked always-on."
  warn "Devices may not sync when not simultaneously online."
fi

note "Registering ${#_IDS[@]} peer device(s)... ${DIM}[demo: fake API]${RESET}"
for i in "${!_IDS[@]}"; do
  [[ -z "${_IDS[$i]}" ]] && continue
  sleep 0.2
  ok "device ${_NAMES[$i]}: registered"
done

note "Configuring folders... ${DIM}[demo: fake API]${RESET}"
sleep 0.3
ok "folder claude (post): synced with ${#_IDS[@]} peer(s)"
[[ -n "$extra_dir" ]] && { sleep 0.3; ok "folder ${extra_label} (post): synced with ${#_IDS[@]} peer(s)"; }

# ---------- 6. Summary ----------

echo
echo "${GREEN}${BOLD}════════════════════════════════════════════════════════════════════${RESET}"
echo "${GREEN}${BOLD}  ✓ Setup complete on this device${RESET}"
echo "${GREEN}${BOLD}════════════════════════════════════════════════════════════════════${RESET}"
echo
echo "  ${BOLD}This device's ID${RESET} (share with future peers):"
echo "  ${GREEN}${FAKE_SELF_ID}${RESET}"
echo
echo "  ${BOLD}Web UI:${RESET}        http://127.0.0.1:8384"
echo "  ${BOLD}Config file:${RESET}   /tmp/demo-config.env ${DIM}(fake)${RESET}"
echo

if [[ "${#_IDS[@]}" -gt 0 ]]; then
  echo "  ${BOLD}What happens now:${RESET}"
  echo "    Sync starts automatically once the other side has YOUR device ID too."
  echo
  echo "  ${BOLD}On the other device, make sure it knows about you:${RESET}"
  for i in "${!_IDS[@]}"; do
    [[ -z "${_IDS[$i]}" ]] && continue
    echo "    ${BOLD}${_NAMES[$i]}${RESET}: re-run the wizard there with ${BOLD}y${RESET} when asked, paste ${GREEN}${FAKE_SELF_ID}${RESET}"
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
echo "${YELLOW}${BOLD}  ⚠ DEMO MODE — none of the above was actually applied.${RESET}"
echo "${YELLOW}  To run the real wizard: ${BOLD}./scripts/bootstrap.sh${RESET}"
echo
