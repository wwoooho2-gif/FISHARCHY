#!/bin/bash
# publish-release.sh - split (if needed), checksum and publish a FISHARCHY ISO.
#
#   ./tools/publish-release.sh [path/to/iso] [tag]
#
# Writes SHA256SUMS covering FISHARCHY.iso and every FISHARCHY.iso.part-* file
# and uploads it with them. Needs the GitHub CLI (gh) logged in.

set -euo pipefail

die() { echo "publish-release: $*" >&2; exit 1; }

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
repo=${GH_REPO:-wwoooho2-gif/FISHARCHY}
iso=${1:-}
tag=${2:-v1.0.0}
downloads=${FISHARCHY_DOWNLOADS:-$HOME/Downloads}
limit=$((1900 * 1024 * 1024)) # comfortably below GitHub's 2 GiB asset cap

if command -v gh >/dev/null 2>&1; then
  gh_cmd() { gh "$@"; }
elif command -v mise >/dev/null 2>&1; then
  gh_cmd() { mise x gh@2.103.3 -- gh "$@"; }
else
  die "missing required command 'gh' (install the GitHub CLI and run 'gh auth login')"
fi
command -v sha256sum >/dev/null 2>&1 || die "missing required command 'sha256sum'"

if [[ -z $iso ]]; then
  # Newest ISO in the build tree, or in FISHARCHY_RELEASE_DIR if you set it.
  iso=$(find "$root/build-work/omarchy-iso/release" "${FISHARCHY_RELEASE_DIR:-/nonexistent}" \
    -maxdepth 1 -name '*.iso' -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -1 | cut -d' ' -f2-)
fi
[[ -n $iso && -f $iso ]] || die "no ISO found; pass one explicitly"

mkdir -p "$downloads"
cp -f -- "$iso" "$downloads/FISHARCHY.iso"
iso=$downloads/FISHARCHY.iso
size=$(stat -c %s "$iso")

rm -f "$downloads"/FISHARCHY.iso.part-* "$downloads"/SHA256SUMS "$downloads"/FISHARCHY.iso.sha256
split_release=0
if (( size > limit )); then
  split_release=1
  (cd "$downloads" && split -b 1900M -d -a 2 FISHARCHY.iso FISHARCHY.iso.part-)
fi

# One SHA256SUMS: the whole ISO plus every part.
(
  cd "$downloads"
  shopt -s nullglob
  sha256sum FISHARCHY.iso FISHARCHY.iso.part-* >SHA256SUMS
) || die "could not create SHA256SUMS"
[[ -s $downloads/SHA256SUMS ]] || die "could not create SHA256SUMS"
sha=$(awk '$2 == "FISHARCHY.iso" {print $1}' "$downloads/SHA256SUMS")

if (( split_release )); then
  assets=("$downloads"/FISHARCHY.iso.part-* "$downloads/SHA256SUMS")
else
  assets=("$iso" "$downloads/SHA256SUMS")
fi

notes=$(mktemp)
trap 'rm -f "$notes"' EXIT
{
  echo 'FISHARCHY - a clean, neon Omarchy ISO with KDE Plasma.'
  echo
  echo '## Download and verify'
  echo
  if (( split_release )); then
    echo 'GitHub caps release assets at 2 GiB, so this ISO is split. Download every'
    echo '`FISHARCHY.iso.part-*` file and `SHA256SUMS` into one directory, then:'
    echo
    echo '```bash'
    echo './tools/reassemble-iso.sh ~/Downloads ~/Downloads/FISHARCHY.iso'
    echo '```'
    echo
    echo 'The script checks every part and the joined ISO against `SHA256SUMS`.'
  else
    echo 'Download `FISHARCHY.iso` and `SHA256SUMS` into one directory, then run'
    echo '`sha256sum -c SHA256SUMS`.'
  fi
  echo
  echo "**SHA-256 of FISHARCHY.iso:** \`$sha\`"
  echo
  echo '## Included'
  echo
  echo '- KDE Plasma (Wayland) desktop, no Hyprland'
  echo '- Neon Plymouth splash and SDDM login (`#0d1a3d` / `#19e6ff`)'
  echo '- No preinstalled Omarchy desktop apps, web apps, TUI wrappers, or mise tools'
  echo
  echo '## Write to USB'
  echo
  echo 'Run `lsblk` first and find your USB stick by its size and name. Writing to'
  echo 'the wrong device destroys its data.'
  echo
  echo '```bash'
  echo 'sudo dd if=~/Downloads/FISHARCHY.iso of=/dev/sdX bs=16M status=progress oflag=sync'
  echo '```'
  echo
  echo 'Replace `/dev/sdX` with the whole USB device (not a partition such as `sdX1`).'
} >"$notes"

gh_cmd release create "$tag" "${assets[@]}" \
  --repo "$repo" \
  --title "FISHARCHY ${tag#v}" \
  --notes-file "$notes" \
  --latest

gh_cmd release view "$tag" --repo "$repo" --json url -q .url
