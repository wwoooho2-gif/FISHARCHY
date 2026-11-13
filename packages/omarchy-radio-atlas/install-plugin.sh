#!/bin/bash

set -euo pipefail

if (( EUID == 0 )); then
  echo "omarchy-radio-atlas-install: run as your normal user" >&2
  exit 1
fi

state="$HOME/.local/state/omarchy-radio-atlas"
marker="$state/plugin-installed"
[[ -f $marker ]] && exit 0

src=/usr/share/omarchy-radio-atlas/plugin
dst="$HOME/.config/omarchy/plugins/akshar.radio-atlas"

[[ -d $src ]] || {
  echo "omarchy-radio-atlas-install: packaged plugin missing at $src" >&2
  exit 1
}

mkdir -p "$(dirname -- "$dst")"
if [[ -e $dst || -L $dst ]]; then
  echo "Radio Atlas is already installed at $dst"
else
  cp -a -- "$src" "$dst"
  echo "Installed Radio Atlas into $dst"
fi

command -v omarchy-shell >/dev/null 2>&1 &&
  omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true

mkdir -p "$state"
touch "$marker"
