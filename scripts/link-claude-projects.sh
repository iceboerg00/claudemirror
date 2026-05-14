#!/usr/bin/env bash
# link-claude-projects.sh
# Cross-platform fix for Claude Code session resume on Linux/macOS
# after syncing project folders from a Windows machine.
#
# Claude derives the project folder name from the absolute working directory:
#   Windows:  pwd=C:\Users\Mike\Desktop\myproject  -> projects/C--Users-Mike-Desktop-myproject
#   Linux:    pwd=/home/mike/Desktop/myproject     -> projects/-home-mike-Desktop-myproject
#   macOS:    pwd=/Users/mike/Desktop/myproject    -> projects/-Users-mike-Desktop-myproject
#
# This script creates symlinks Linux-name -> Windows-name so `claude --resume`
# finds Windows-originated sessions. Any new writes flow through the symlink
# into the canonical (Windows-named) folder and sync back.

set -u

PROJECTS_DIR="${1:-$HOME/.claude/projects}"
[[ -d "$PROJECTS_DIR" ]] || { echo "Not found: $PROJECTS_DIR"; exit 1; }
cd "$PROJECTS_DIR"

# Detect OS prefix for our home: Linux "-home-USER" or macOS "-Users-USER"
OS="$(uname -s)"
case "$OS" in
  Linux*)  PREFIX="-home-${USER,,}" ;;  # lowercase username on linux
  Darwin*) PREFIX="-Users-$USER" ;;
  *) echo "Skipping symlinks: unsupported OS $OS"; exit 0 ;;
esac

linked=0; relinked=0; skipped=0
for d in C--*; do
  [[ -d "$d" && ! -L "$d" ]] || continue

  # The Windows path starts with "C--Users-<WinUser>-..." -- replace the
  # whole prefix up to and including the username with our local prefix.
  # Simple heuristic: replace "C--Users-<word>" with "$PREFIX".
  linux_name=$(echo "$d" | sed -E "s|^C--Users-[^-]+|$PREFIX|")

  if [[ -L "$linux_name" ]]; then
    current=$(readlink -- "$linux_name")
    if [[ "$current" == "$d" ]]; then skipped=$((skipped + 1)); continue; fi
    if ln -sfn -- "$d" "$linux_name"; then
      echo "    relink $linux_name -> $d"
      relinked=$((relinked + 1))
    fi
  elif [[ -e "$linux_name" ]]; then
    skipped=$((skipped + 1))
  else
    if ln -s -- "$d" "$linux_name" 2>/dev/null; then
      echo "    link   $linux_name -> $d"
      linked=$((linked + 1))
    fi
  fi
done

echo "    summary: new=$linked relinked=$relinked skipped=$skipped"
