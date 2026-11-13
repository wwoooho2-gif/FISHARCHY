#!/bin/bash
# Runs after the 10-40 FISHARCHY hooks. If Radio Atlas or the FISHYLAYOUT
# plugin didn't land, run the repair once. Output goes to a log file.
set -uo pipefail

state="$HOME/.local/state/fisharchy"
marker="$state/selfheal-done"
[[ -f $marker ]] && exit 0
mkdir -p "$state"

plugins="$HOME/.config/omarchy/plugins"
missing=0
[[ -d $plugins/akshar.radio-atlas ]] || missing=1
[[ -d $plugins/furina.omarchy-suite ]] || missing=1

if (( missing )); then
  echo "$(date): something missing, running repair" >>"$state/selfheal.log"
  /usr/share/fisharchy/fisharchy-repair.sh --repair >>"$state/selfheal.log" 2>&1 || true
else
  echo "$(date): all good, nothing to repair" >>"$state/selfheal.log"
fi

touch "$marker"
