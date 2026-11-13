#!/bin/bash

set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
work=${FISHARCHY_WORK_DIR:-$root/build-work}
builder=$work/omarchy-iso
pkgdest=$work/pkgs
custom=$builder/custom-packages
OMARCHY_ISO_COMMIT=${OMARCHY_ISO_COMMIT:-38d8d05537a2442a73a92c0e1ccce0fb670f369a}
GH_OWNER=${GH_OWNER:-wwoooho2-gif}

# Universal build: one ISO for NVIDIA and non-NVIDIA machines.
# The stock Omarchy installer detects the GPU at install time and picks the
# right driver, so we keep every driver/firmware package in the image.
# Run with FISHARCHY_KEEP_HARDWARE=0 ./build-fisharchy.sh for the old lean build.
export FISHARCHY_KEEP_HARDWARE=${FISHARCHY_KEEP_HARDWARE:-1}

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "build-fisharchy: missing required command: $1" >&2
    exit 1
  }
}

need git
need makepkg
need docker
need bsdtar

mkdir -p "$work" "$pkgdest"

# A cached builder tree or package mirror from the other mode is the usual
# cause of a red installer failure screen, so reset it when the mode changes.
mode_file=$work/.fisharchy-mode
if [[ -f $mode_file && $(cat "$mode_file") != "$FISHARCHY_KEEP_HARDWARE" ]]; then
  echo "==> Build mode changed; clearing cached ISO build state"
  rm -rf -- "$work/omarchy-iso/release" "$work/omarchy-iso/.cache" "$work/omarchy-iso/custom-packages"
  docker volume ls -q 2>/dev/null | grep -i omarchy | xargs -r docker volume rm >/dev/null 2>&1 || true
fi
echo "$FISHARCHY_KEEP_HARDWARE" > "$mode_file"

clone_or_update() {
  local url=$1 dir=$2
  if [[ -d $dir/.git ]]; then
    git -C "$dir" pull --ff-only --quiet
  else
    rm -rf -- "$dir"
    git clone --quiet "$url" "$dir"
  fi
}

build_package() {
  local dir=$1
  printf '\n==> Building %s\n' "${dir##*/}"
  (
    cd -- "$dir"
    PKGDEST="$pkgdest" makepkg -f --nodeps --noconfirm
  )
}

if [[ ! -d $builder/.git ]]; then
  git clone --quiet https://github.com/omacom-io/omarchy-iso.git "$builder"
fi
git -C "$builder" fetch --quiet origin
git -C "$builder" checkout --quiet --force "$OMARCHY_ISO_COMMIT"
git -C "$builder" submodule update --init --recursive --jobs=8

if git -C "$builder" apply --check "$root/iso/fisharchy.patch" 2>/dev/null; then
  git -C "$builder" apply "$root/iso/fisharchy.patch"
  echo "==> Applied iso/fisharchy.patch"
elif git -C "$builder" apply --reverse --check "$root/iso/fisharchy.patch" 2>/dev/null; then
  echo "==> iso/fisharchy.patch already applied"
else
  echo "build-fisharchy: the builder has diverged; cannot apply iso/fisharchy.patch" >&2
  exit 1
fi

clone_or_update "https://github.com/$GH_OWNER/omarchy-boot-branding.git" "$work/omarchy-boot-branding"
clone_or_update "https://github.com/$GH_OWNER/omarchy-fish-theme.git" "$work/omarchy-fish-theme"
clone_or_update "https://github.com/$GH_OWNER/FISHYLAYOUT.git" "$work/FISHYLAYOUT"

build_package "$work/omarchy-boot-branding"
build_package "$work/omarchy-fish-theme"
build_package "$work/FISHYLAYOUT"

clone_or_update https://github.com/AksharP5/omarchy-radio-atlas.git "$work/radio-atlas"
radio_pkg=$work/pkgbuilds/omarchy-radio-atlas
rm -rf -- "$radio_pkg"
mkdir -p "$radio_pkg/plugin"
(cd -- "$work/radio-atlas" && tar --exclude=.git -cf - .) | tar -xf - -C "$radio_pkg/plugin"
cp "$root"/packages/omarchy-radio-atlas/PKGBUILD \
  "$root"/packages/omarchy-radio-atlas/install-plugin.sh \
  "$root"/packages/omarchy-radio-atlas/hook-plugin.sh "$radio_pkg/"
build_package "$radio_pkg"

build_package "$root/packages/omarchy-no-preinstalls"

mkdir -p "$custom"
cp -f -- "$pkgdest"/*.pkg.tar.zst "$custom/"
ls -1 "$custom"

cd -- "$builder"
./bin/omarchy-iso-make --no-boot-offer --keep-pkg-cache

printf '\nFISHARCHY ISO(s):\n'
ls -lh "$builder"/release/*.iso
