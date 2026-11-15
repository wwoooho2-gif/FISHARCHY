#!/bin/bash
# publish-release.sh [ISO] [TAG]
# Copies the ISO to a download folder, splits it if it exceeds GitHub's 2 GiB asset cap, writes
# SHA256SUMS (ISO and every part) and creates the GitHub release. Never publish a lean ISO.
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=iso/versions.env
source "$root/iso/versions.env"

repo=${GH_REPO:-wwoooho2-gif/FISHARCHY}
iso=${1:-}
tag=${2:-v$FISHARCHY_VERSION}
downloads=${FISHARCHY_DOWNLOADS:-$HOME/Downloads}
limit=$((1900 * 1024 * 1024)) # comfortably below GitHub's 2 GiB asset cap

die() { echo "publish-release: $*" >&2; exit 1; }

gh_cmd() {
  if command -v gh >/dev/null 2>&1; then
    gh "$@"
  elif command -v mise >/dev/null 2>&1; then
    mise x gh@latest -- gh "$@"
  else
    die "the GitHub CLI 'gh' is required (pacman -S github-cli)."
  fi
}

if [[ -z $iso ]]; then
  iso=$root/fisharchy.iso
fi
[[ -f $iso ]] || die "no ISO found; pass one explicitly"

# Refuse to publish a lean image: it only works on the PC it was built for.
if [[ -f $root/build-work/.fisharchy-mode ]] && grep -q 'hardware=lean' "$root/build-work/.fisharchy-mode"; then
  die "the last build was --lean (this PC only). Build with --universal before publishing."
fi

mkdir -p "$downloads"
cp -f -- "$iso" "$downloads/fisharchy.iso"
size=$(stat -c %s "$downloads/fisharchy.iso")

rm -f -- "$downloads"/fisharchy.iso.part-* "$downloads/SHA256SUMS"
assets=("$downloads/fisharchy.iso")
if (( size > limit )); then
  (cd "$downloads" && split -b 1900M -d -a 2 fisharchy.iso fisharchy.iso.part-)
  assets=("$downloads"/fisharchy.iso.part-*)
fi
# SHA256SUMS lists the ISO and every part; reassemble-iso.sh checks both.
(cd "$downloads" && sha256sum -- fisharchy.iso fisharchy.iso.part-* 2>/dev/null >SHA256SUMS || sha256sum -- fisharchy.iso >SHA256SUMS)
assets+=("$downloads/SHA256SUMS")
sha=$(awk '$2 == "fisharchy.iso" {print $1}' "$downloads/SHA256SUMS")

if (( size > limit )); then
  read -r -d '' how <<'SPLIT' || true
This ISO is split because GitHub caps release assets at 2 GiB. Download every
`fisharchy.iso.part-*` file and `SHA256SUMS` into one directory, then join and verify:

```bash
./tools/reassemble-iso.sh ~/Downloads ~/Downloads/fisharchy.iso
```
SPLIT
else
  how='Download `fisharchy.iso` and `SHA256SUMS`, then verify with `sha256sum -c --ignore-missing SHA256SUMS`.'
fi

notes=$(mktemp)
trap 'rm -f "$notes"' EXIT
cat >"$notes" <<NOTES
FISHARCHY — a clean, neon, Fish-themed Omarchy ISO.

## Download

$how

**SHA-256 (fisharchy.iso):** \`$sha\`

## Included

- Neon Plymouth splash and SDDM login (\`#0d1a3d\` / \`#19e6ff\`)
- Fish theme as the default desktop theme
- FISHYLAYOUT dashboard and the FISHARCHY bar/dock layout
- Radio Atlas plugin, enabled in the bar
- Performance and stability layer (zram, OOM handling, crash log); CPU mitigations ON by default
- No preinstalled Omarchy desktop apps, web apps, TUI wrappers, or mise tools

## Write to USB

Find your USB stick first with \`lsblk\`, then replace \`/dev/sdX\` with the whole device (not a partition).
Everything on it is erased.

\`\`\`bash
lsblk -o NAME,SIZE,MODEL,TRAN
sudo dd if=~/Downloads/fisharchy.iso of=/dev/sdX bs=16M status=progress oflag=sync
\`\`\`
NOTES

gh_cmd release create "$tag" "${assets[@]}" \
  --repo "$repo" \
  --title "FISHARCHY ${tag#v}" \
  --notes-file "$notes" \
  --latest

gh_cmd release view "$tag" --repo "$repo" --json url -q .url
