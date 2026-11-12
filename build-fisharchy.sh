#!/bin/bash
# Build the FISHARCHY Omarchy ISO from scratch.
#
# Needs: git, base-devel (makepkg), docker (with sudo if the user is not in the
# docker group), and GitHub credentials for the private wwoooho2-gif repos
# (gh auth setup-git). Everything else happens in the ISO build container.
#
# Usage: ./build-fisharchy.sh
# Output: build-work/omarchy-iso/release/*.iso

set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
work=${FISHARCHY_WORK_DIR:-$root/build-work}
builder=$work/omarchy-iso
pkgdest=$work/pkgs
custom=$builder/custom-packages
OMARCHY_ISO_COMMIT=${OMARCHY_ISO_COMMIT:-38d8d05537a2442a73a92c0e1ccce0fb670f369a}
GH_OWNER=${GH_OWNER:-wwoooho2-gif}

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

# 1. The Omnarchy ISO builder, pinned to the commit iso/fisharchy.patch targets.
if [[ ! -d $builder/.git ]]; then
  git clone --quiet https://github.com/omacom-io/omarchy-iso.git "$builder"
fi
git -C "$builder" fetch --quiet origin
git -C "$builder" checkout --quiet "$OMARCHY_ISO_COMMIT"
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

# 2. The custom packages, built from their upstream repositories.
clone_or_update "https://github.com/$GH_OWNER/omarchy-boot-branding.git" "$work/omarchy-boot-branding"
clone_or_update "https://github.com/$GH_OWNER/omarchy-fish-theme.git" "$work/omarchy-fish-theme"
clone_or_update "https://github.com/$GH_OWNER/FISHYLAYOUT.git" "$work/FISHYLAYOUT"

build_package "$work/omarchy-boot-branding"
build_package "$work/omarchy-fish-theme"
build_package "$work/FISHYLAYOUT"

# Radio Atlas is upstream; its package recipe lives in this repository.
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

# 3. Stage the archives where the patched builder looks for them.
mkdir -p "$custom"
cp -f -- "$pkgdest"/*.pkg.tar.zst "$custom/"
ls -1 "$custom"

# 4. Build the ISO. --keep-pkg-cache avoids the interactive purge of the host
#    pacman cache; --no-boot-offer makes the build unattended.
cd -- "$builder"
./bin/omarchy-iso-make --no-boot-offer --keep-pkg-cache

printf '\nFISHARCHY ISO(s):\n'
ls -lh "$builder"/release/*.iso
