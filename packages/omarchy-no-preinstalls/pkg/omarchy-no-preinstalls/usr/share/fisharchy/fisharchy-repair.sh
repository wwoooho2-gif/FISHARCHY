#!/bin/bash
# fisharchy-repair.sh
#
# Re-runs the FISHARCHY first-boot hooks (fish theme, FISHYLAYOUT, Radio Atlas,
# bar layout) and adds a "Fish Installer" entry to the launcher (super+space).
#
#   ./fisharchy-repair.sh              install the menu entry, then repair
#   ./fisharchy-repair.sh --repair     repair only (what the menu entry runs)
#   ./fisharchy-repair.sh --menu-only  only install the menu entry

set -uo pipefail

if (( EUID == 0 )); then
  echo "Run this as your normal user, not root." >&2
  exit 1
fi

self=$(readlink -f -- "${BASH_SOURCE[0]}")
install_dir="$HOME/.local/share/fisharchy"
script="$install_dir/fisharchy-repair.sh"
apps="$HOME/.local/share/applications"
skel_hooks=/etc/skel/.config/omarchy/hooks/post-boot.d
user_hooks="$HOME/.config/omarchy/hooks/post-boot.d"

install_menu() {
  mkdir -p "$install_dir" "$apps"
  [[ $self == "$script" ]] || cp -f -- "$self" "$script"
  chmod +x "$script"

  cat >"$apps/fisharchy-installer.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Fish Installer
GenericName=FISHARCHY repair
Comment=Reinstall the Fish layout, theme and Radio Atlas
Exec=xdg-terminal-exec bash -c '"$script" --repair; echo; read -rp "Done. Press Enter to close. "'
Icon=system-software-install
Terminal=false
Categories=System;Utility;
Keywords=fish;fisharchy;layout;install;radio;
EOF
  command -v update-desktop-database >/dev/null 2>&1 &&
    update-desktop-database "$apps" >/dev/null 2>&1 || true
  echo "Menu entry installed: $apps/fisharchy-installer.desktop"
}

repair() {
  echo "==> Clearing 'already installed' markers"
  rm -f "$HOME/.local/state/omarchy-radio-atlas/plugin-installed"
  # Other hooks may keep their own markers; clear any that look fish-related.
  find "$HOME/.local/state" -maxdepth 3 -type f \
    \( -iname '*fish*' -o -iname '*radio-atlas*' \) -print -delete 2>/dev/null

  echo
  echo "==> Running first-boot hooks"
  mkdir -p "$user_hooks"
  failed=0
  for name in 10-fish-theme 20-fishylayout-plugin 30-radio-atlas-plugin 40-fish-layout; do
    hook=
    for dir in "$skel_hooks" "$user_hooks"; do
      [[ -x $dir/$name ]] && { hook=$dir/$name; break; }
    done
    if [[ -z $hook ]]; then
      echo "  MISSING  $name  (the package that ships it is not in this install)"
      failed=1
      continue
    fi
    echo "  RUNNING  $name"
    if "$hook"; then
      echo "  OK       $name"
    else
      echo "  FAILED   $name (exit $?)"
      failed=1
    fi
  done

  echo
  command -v omarchy-shell >/dev/null 2>&1 &&
    omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true

  if (( failed )); then
    echo "Some steps were missing or failed. For MISSING hooks, check with:"
    echo "  pacman -Q omarchy-fishylayout omarchy-radio-atlas omarchy-fish-theme"
    echo "If a package is not installed, it never made it into the ISO build."
    return 1
  fi
  echo "All hooks ran. Log out and back in if the layout hasn't changed."
}

case "${1:-}" in
  --repair)    repair ;;
  --run)       repair; echo; read -rp "Done. Press Enter to close. " _ ;;
  --menu-only) install_menu ;;
  *)           install_menu; echo; repair ;;
esac
