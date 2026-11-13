#!/bin/bash

set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
repo=${GH_REPO:-wwoooho2-gif/FISHARCHY}
iso=${1:-}
tag=${2:-v1.0.0}
downloads=${FISHARCHY_DOWNLOADS:-$HOME/Downloads}
limit=$((1900 * 1024 * 1024)) # comfortably below GitHub's 2 GiB asset cap

gh_cmd() {
  if command -v gh >/dev/null 2>&1; then
    gh "$@"
  else
    mise x gh@2.103.3 -- gh "$@"
  fi
}

if [[ -z $iso ]]; then
  iso=$(find "$root/build-work" "$root/../omarchy-iso/release" /home/furina/Work/omarchy-iso/release \
    -maxdepth 1 -name '*.iso' -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -1 | cut -d' ' -f2-)
fi
if [[ ! -f $iso ]]; then
  echo "publish-release: no ISO found; pass one explicitly" >&2
  exit 1
fi

mkdir -p "$downloads"
cp -f -- "$iso" "$downloads/FISHARCHY.iso"
iso=$downloads/FISHARCHY.iso
size=$(stat -c %s "$iso")
sha=$(sha256sum "$iso" | cut -d' ' -f1)
printf '%s  FISHARCHY.iso\n' "$sha" >"$downloads/FISHARCHY.iso.sha256"

rm -f "$downloads"/FISHARCHY.iso.part-*
assets=("$iso" "$downloads/FISHARCHY.iso.sha256")
if (( size > limit )); then
  (cd "$downloads" && split -b 1900M -d -a 2 FISHARCHY.iso FISHARCHY.iso.part-)
  assets=("$downloads"/FISHARCHY.iso.part-* "$downloads/FISHARCHY.iso.sha256")
fi

notes=$(mktemp)
trap 'rm -f "$notes"' EXIT
cat >"$notes" <<EOF
FISHARCHY — a clean, neon, Fish-themed Omarchy ISO.

## Download

$(if (( size > limit )); then
  cat <<'SPLIT'
This ISO is split because GitHub caps release assets at 2 GiB. Download every
\`FISHARCHY.iso.part-*\` file and \`FISHARCHY.iso.sha256\` into one directory,
then reassemble and verify:

\`\`\`bash
./tools/reassemble-iso.sh ~/Downloads ~/Downloads/FISHARCHY.iso
\`\`\`
SPLIT
else
  echo 'Download `FISHARCHY.iso`, then verify it with `sha256sum -c FISHARCHY.iso.sha256`.'
fi)

**SHA-256:** \`$sha\`

## Included

- Neon Plymouth splash and SDDM login (\`#0d1a3d\` / \`#19e6ff\`)
- Fish theme as the default desktop theme
- FISHYLAYOUT dashboard and the FISHARCHY bar/dock layout
- Radio Atlas plugin, enabled in the bar
- No preinstalled Omarchy desktop apps, web apps, TUI wrappers, or mise tools

## Write to USB

\`\`\`bash
sudo dd if=~/Downloads/FISHARCHY.iso of=/dev/sdX bs=16M status=progress oflag=sync
\`\`\`

Replace \`/dev/sdX\` with the USB device (not a partition).
EOF

gh_cmd release create "$tag" "${assets[@]}" \
  --repo "$repo" \
  --title "FISHARCHY 1.0.0" \
  --notes-file "$notes" \
  --latest

gh_cmd release view "$tag" --repo "$repo" --json url -q .url
