#!/bin/bash
# build-fisharchy.sh - build the FISHARCHY ISO from scratch.
# See `./build-fisharchy.sh --help`. Rebuilding needs access to the private package repos.

set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=iso/versions.env
source "$root/iso/versions.env"

work=${FISHARCHY_WORK_DIR:-$root/build-work}
builder=$work/omarchy-iso
pkgdest=$work/pkgs
custom=$builder/custom-packages
OMARCHY_ISO_COMMIT=${OMARCHY_ISO_COMMIT_OVERRIDE:-$OMARCHY_ISO_COMMIT}
GH_OWNER=${GH_OWNER:-wwoooho2-gif}

die() { echo "build-fisharchy: $*" >&2; exit 1; }

usage() {
  cat <<'USAGE'
usage: build-fisharchy.sh [hardware] [performance] [--pin]

hardware (what goes in the image):
  --universal          default. One ISO for NVIDIA, AMD and Intel; every driver and firmware family stays in.
  --lean               ONLY for the exact PC it is built on. Drops other GPUs, radios, firmware and
                       non-English language files. May not boot or have working Wi-Fi, Bluetooth or
                       graphics on any other machine. Never publish a lean ISO.

performance (what the image boots with):
  --safe               default. CPU security mitigations stay ON.
  --max-performance    turns mitigations off (mitigations=off split_lock_detect=off) for people who
                       accept the security risk. Can be switched later with `fisharchy-mode`.

other:
  --pin                rewrite iso/versions.env with the exact commits that were built
  -h, --help           this text

environment (same effect as the flags):
  FISHARCHY_KEEP_HARDWARE=1|0        1 = universal (default), 0 = lean
  FISHARCHY_PERFORMANCE=safe|max     safe is the default (old values 0 = safe, 1 = max still work)
  FISHARCHY_WORK_DIR=PATH            build directory (default ./build-work)
Rebuilding requires access to the private repos omarchy-boot-branding, omarchy-fish-theme and
FISHYLAYOUT (run `gh auth setup-git`). Everyone else should use the released ISO.
USAGE
}

pin=0
for arg in "$@"; do
  case $arg in
    --lean) export FISHARCHY_KEEP_HARDWARE=0 ;;
    --universal) export FISHARCHY_KEEP_HARDWARE=1 ;;
    --safe|--hardened) export FISHARCHY_PERFORMANCE=safe ;;   # --hardened is the old name for --safe
    --max-performance) export FISHARCHY_PERFORMANCE=max ;;
    --pin) pin=1 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "unknown option: $arg" ;;
  esac
done

export FISHARCHY_KEEP_HARDWARE=${FISHARCHY_KEEP_HARDWARE:-1}
case ${FISHARCHY_PERFORMANCE:-safe} in
  safe|0) FISHARCHY_PERFORMANCE=safe ;;
  max|1) FISHARCHY_PERFORMANCE=max ;;
  *) die "FISHARCHY_PERFORMANCE must be 'safe' or 'max' (got '${FISHARCHY_PERFORMANCE}')" ;;
esac
export FISHARCHY_PERFORMANCE

need() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command '$1'. $2"
}
need git "Install git (pacman -S git)."
need makepkg "Run this on Arch Linux or an Arch container (pacman -S base-devel)."
need docker "Install Docker and start it (pacman -S docker; sudo systemctl enable --now docker)."
need bsdtar "Install libarchive (pacman -S libarchive)."
docker info >/dev/null 2>&1 || die "Docker is installed but not usable. Start it and add yourself to the docker group (sudo usermod -aG docker \$USER, then log in again)."

mkdir -p "$work" "$pkgdest"

# Disk space: the ISO build downloads several GB and needs about 20 GB free.
free_gb=$(df -Pk "$work" | awk 'NR==2 {print int($4/1024/1024)}')
if (( free_gb < 20 )); then
  echo "WARNING: only ${free_gb} GB free in $work; the build needs about 20 GB and may fail." >&2
fi

hw_name=universal; [[ $FISHARCHY_KEEP_HARDWARE == 1 ]] || hw_name=lean
if [[ $hw_name == lean ]]; then
  cat >&2 <<'WARN'
################################################################################
# LEAN BUILD: this ISO is for the exact PC it was built for.
# It may not boot, or may have no working Wi-Fi, Bluetooth or graphics, on any
# other machine. Do not publish it. Use --universal for a shareable image.
################################################################################
WARN
fi

# Fail early if the private package repos are not reachable by this account.
export GIT_TERMINAL_PROMPT=0
for repo in omarchy-boot-branding omarchy-fish-theme FISHYLAYOUT; do
  if ! git ls-remote --quiet "https://github.com/$GH_OWNER/$repo.git" HEAD >/dev/null 2>&1; then
    die "cannot reach https://github.com/$GH_OWNER/$repo (private). Only the repository owner can rebuild the image; everyone else should use the released ISO. Owner: run 'gh auth setup-git' and retry."
  fi
done

# A cached builder tree or package mirror from another mode causes red installer failures.
mode_file=$work/.fisharchy-mode
mode_key="hardware=$hw_name performance=$FISHARCHY_PERFORMANCE"
if [[ -f $mode_file && $(cat "$mode_file") != "$mode_key" ]]; then
  echo "==> Build mode changed; clearing cached ISO build state"
  rm -rf -- "$work/omarchy-iso/release" "$work/omarchy-iso/.cache" "$work/omarchy-iso/custom-packages"
  docker volume ls -q 2>/dev/null | grep -i omarchy | xargs -r docker volume rm >/dev/null 2>&1 || true
fi
echo "$mode_key" >"$mode_file"

# Check a repo out at a ref (branch, tag or SHA) and print the resolved commit.
checkout_ref() {
  local url=$1 dir=$2 ref=$3
  if [[ ! -d $dir/.git ]]; then
    rm -rf -- "$dir"
    git clone --quiet "$url" "$dir" || die "cannot clone $url"
  fi
  git -C "$dir" fetch --quiet --tags origin || die "cannot fetch $url"
  git -C "$dir" reset --hard --quiet
  git -C "$dir" checkout --quiet --force --detach "origin/$ref" 2>/dev/null ||
    git -C "$dir" checkout --quiet --force --detach "$ref" ||
    die "ref '$ref' not found in $url"
  git -C "$dir" rev-parse HEAD
}

build_package() {
  local dir=$1
  printf '\n==> Building %s\n' "${dir##*/}"
  (
    cd -- "$dir"
    PKGDEST="$pkgdest" makepkg -f --nodeps --noconfirm
  )
}

# Builder: pinned commit, tree reset so a leftover patched copy cannot cause a false "diverged" error.
if [[ ! -d $builder/.git ]]; then
  git clone --quiet https://github.com/omacom-io/omarchy-iso.git "$builder" || die "cannot clone omacom-io/omarchy-iso"
fi
git -C "$builder" fetch --quiet origin || die "cannot fetch omacom-io/omarchy-iso"
git -C "$builder" cat-file -e "${OMARCHY_ISO_COMMIT}^{commit}" 2>/dev/null ||
  die "pinned omarchy-iso commit $OMARCHY_ISO_COMMIT cannot be fetched; update OMARCHY_ISO_COMMIT in iso/versions.env"
git -C "$builder" reset --hard --quiet
# Keep the download cache and previous releases; remove everything else the patch may have left.
git -C "$builder" clean -fdxq -e .cache -e release
git -C "$builder" checkout --quiet --force "$OMARCHY_ISO_COMMIT"
git -C "$builder" submodule update --init --recursive --jobs=8

git -C "$builder" apply --check "$root/iso/fisharchy.patch" 2>/dev/null ||
  die "iso/fisharchy.patch does not apply to omarchy-iso $OMARCHY_ISO_COMMIT. The upstream builder changed or the patch is broken; fix the patch or pin an older commit."
git -C "$builder" apply "$root/iso/fisharchy.patch"
echo "==> Applied iso/fisharchy.patch"

branding_sha=$(checkout_ref "https://github.com/$GH_OWNER/omarchy-boot-branding.git" "$work/omarchy-boot-branding" "$BRANDING_REF")
theme_sha=$(checkout_ref "https://github.com/$GH_OWNER/omarchy-fish-theme.git" "$work/omarchy-fish-theme" "$FISH_THEME_REF")
layout_sha=$(checkout_ref "https://github.com/$GH_OWNER/FISHYLAYOUT.git" "$work/FISHYLAYOUT" "$FISHYLAYOUT_REF")
radio_sha=$(checkout_ref https://github.com/AksharP5/omarchy-radio-atlas.git "$work/radio-atlas" "$RADIO_ATLAS_REF")
tuning_sha=$(git -C "$root" rev-parse HEAD 2>/dev/null || echo unknown)

build_date=$(date -u +%Y-%m-%dT%H:%MZ)
# Single line, ';'-separated; build-root-image.sh writes it to /etc/fisharchy-release one item per line.
export FISHARCHY_RELEASE_STAMP="fisharchy_version=$FISHARCHY_VERSION;build_date=$build_date;hardware=$hw_name;performance=$FISHARCHY_PERFORMANCE;desktop=hyprland;omarchy_iso_commit=$OMARCHY_ISO_COMMIT;branding_ref=$branding_sha;fish_theme_ref=$theme_sha;fishylayout_ref=$layout_sha;radio_atlas_ref=$radio_sha;fisharchy_repo_ref=$tuning_sha"

echo
echo "FISHARCHY build"
echo "${FISHARCHY_RELEASE_STAMP//;/$'\n'}" | sed 's/^/  /'
echo

# Stale package versions from earlier builds would trip the "multiple custom builds" check.
rm -f -- "$pkgdest"/*.pkg.tar.*

build_package "$work/omarchy-boot-branding"
build_package "$work/omarchy-fish-theme"
build_package "$work/FISHYLAYOUT"

radio_pkg=$work/pkgbuilds/omarchy-radio-atlas
rm -rf -- "$radio_pkg"
mkdir -p "$radio_pkg/plugin"
(cd -- "$work/radio-atlas" && tar --exclude=.git -cf - .) | tar -xf - -C "$radio_pkg/plugin"
cp "$root"/packages/omarchy-radio-atlas/PKGBUILD \
  "$root"/packages/omarchy-radio-atlas/install-plugin.sh \
  "$root"/packages/omarchy-radio-atlas/hook-plugin.sh "$radio_pkg/"
build_package "$radio_pkg"

build_package "$root/packages/omarchy-no-preinstalls"
build_package "$root/packages/fisharchy-tuning"

mkdir -p "$custom"
rm -f -- "$custom"/*.pkg.tar.*
cp -f -- "$pkgdest"/*.pkg.tar.* "$custom/"
ls -1 "$custom"

if (( pin )); then
  sed -i \
    -e "s/^BRANDING_REF=.*/BRANDING_REF=$branding_sha/" \
    -e "s/^FISH_THEME_REF=.*/FISH_THEME_REF=$theme_sha/" \
    -e "s/^FISHYLAYOUT_REF=.*/FISHYLAYOUT_REF=$layout_sha/" \
    -e "s/^RADIO_ATLAS_REF=.*/RADIO_ATLAS_REF=$radio_sha/" \
    "$root/iso/versions.env"
  echo "==> Pinned the four package refs in iso/versions.env"
fi

cd -- "$builder"
./bin/omarchy-iso-make --no-boot-offer --keep-pkg-cache

printf '\nFISHARCHY ISO(s):\n'
ls -lh "$builder"/release/*.iso
# Checksums next to the ISO(s); publish-release.sh adds the split parts.
(cd -- "$builder/release" && sha256sum -- *.iso >SHA256SUMS)
echo "Wrote $builder/release/SHA256SUMS"
[[ $hw_name == lean ]] && echo "REMINDER: this is a LEAN ISO for this PC only. Do not share it." >&2
exit 0
