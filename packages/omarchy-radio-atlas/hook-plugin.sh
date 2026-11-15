#!/bin/bash
# 30-radio-atlas-plugin: first-boot hook. Copies the Radio Atlas plugin into
# ~/.config/omarchy/plugins. Safe to run twice: it keeps a marker file and
# never overwrites an existing plugin directory.
set -euo pipefail
/usr/share/omarchy-radio-atlas/install-plugin.sh
