#!/bin/bash
# 05-remove-preinstalls: first-boot hook. Removes Omarchy's preinstalled web
# apps, TUI wrappers and default mise tools. Safe to run twice: the script it
# calls stops at once if its marker file already exists.
set -euo pipefail
/usr/share/omarchy-clean/remove-preinstalls.sh
