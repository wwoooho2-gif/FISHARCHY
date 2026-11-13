#!/bin/bash

set -euo pipefail

marker="$HOME/.local/state/omarchy/preinstalls-removed"
[[ -f $marker ]] && exit 0

mkdir -p "$HOME/.local/state/omarchy"

command -v omarchy-webapp-remove-all >/dev/null 2>&1 &&
  omarchy-webapp-remove-all >/dev/null 2>&1 || true
command -v omarchy-tui-remove-all >/dev/null 2>&1 &&
  omarchy-tui-remove-all >/dev/null 2>&1 || true
command -v omarchy-mise-default-tools >/dev/null 2>&1 &&
  omarchy-mise-default-tools disable >/dev/null 2>&1 || true

rm -f "$HOME"/.local/bin/codex "$HOME"/.local/bin/claude "$HOME"/.local/bin/agy \
  "$HOME"/.local/bin/copilot "$HOME"/.local/bin/gh "$HOME"/.local/bin/opencode \
  "$HOME"/.local/bin/playwright "$HOME"/.local/bin/playwright-cli "$HOME"/.local/bin/pi \
  "$HOME"/.local/bin/omp "$HOME"/.local/bin/ori "$HOME"/.local/bin/cf \
  "$HOME"/.local/bin/grok "$HOME"/.local/bin/crush "$HOME"/.local/bin/ghui \
  "$HOME"/.local/bin/hunk

touch "$marker"

command -v omarchy-restart-hyprctl >/dev/null 2>&1 &&
  omarchy-restart-hyprctl >/dev/null 2>&1 || true
