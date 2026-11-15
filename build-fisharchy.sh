#!/bin/bash
# build-fisharchy.sh - build the FISHARCHY ISO.
#
# Needs access to the three PRIVATE package repositories, so only the
# repository owner can rebuild. Everyone else should use the released ISO.

set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
work=${FISHARCHY_WORK_DIR:-$root/build-work}
builder=$work/omarchy-iso
pkgdest=$work/pkgs
custom=$builder/custom-packages
GH_OWNER=${GH_OWNER:-wwoooho2-gif}
min_free_gb=20

die() { echo "build-fisharchy: $*" >&2; exit 1; }

usage() {
  cat <<EOF
usage: $0 [hardware] [mode] [other]

hardware (what goes into the image):
  --universal        default. Every GPU driver and firmware family stays in.
  --lean             ONLY for the exact PC you build on (see warning below).

mode (CPU security vs speed; also FISHARCHY_MODE=safe|max):
  --safe             default. CPU mitigations (Spectre/Meltdown/...) stay ON.
  --max-performance  turns mitigations OFF (adds mitigations=off and
                     split_lock_detect=off; nowatchdog is on in both modes). Faster on
                     syscall-heavy work, but you accept the security risk.
  --hardened         deprecated alias for --safe.

other:
  --record-pins      after a good build, write the exact commits that were
                     built into iso/versions.env.
  -h, --help         this help.

WARNING (--lean): the lean ISO is built for the exact PC it was built on. It
drops firmware and drivers for other hardware and may not boot, or may have
no working Wi-Fi, Bluetooth or graphics, on any other machine.

Pinned inputs live in iso/versions.env. Legacy FISHARCHY_PERFORMANCE=0|1 is
still read (0 = safe, 1 = max) but is deprecated.
EOF
}

record_pins=0
mode_from_args=
for arg in "$@"; do
  case $arg in
    --lean) export FISHARCHY_KEEP_HARDWARE=0 ;;
    --universal) export FISHARCHY_KEEP_HARDWARE=1 ;;
    --safe) mode_from_args=safe ;;
    --hardened)
      echo "build-fisharchy: --hardened is deprecated; Safe is now the default (use --safe)" >&2
      mode_from_args=safe ;;
    --max-performance) mode_from_args=max ;;
    --record-pins) record_pins=1 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "unknown option: $arg" ;;
  esac
done

# ---- mode: FISHARCHY_MODE is the one real name; PERFORMANCE is legacy -------
if [[ -z ${FISHARCHY_MODE:-} && -n ${FISHARCHY_PERFORMANCE:-} ]]; then
  case $FISHARCHY_PERFORMANCE in
    0) FISHARCHY_MODE=safe ;;
    1) FISHARCHY_MODE=max ;;
    *) die "FISHARCHY_PERFORMANCE must be 0 or 1 (deprecated; use FISHARCHY_MODE=safe|max)" ;;
  esac
  echo "build-fisharchy: FISHARCHY_PERFORMANCE is deprecated; using FISHARCHY_MODE=$FISHARCHY_MODE" >&2
fi
FISHARCHY_MODE=${mode_from_args:-${FISHARCHY_MODE:-safe}}
[[ $FISHARCHY_MODE == safe || $FISHARCHY_MODE == max ]] ||
  die "FISHARCHY_MODE must be 'safe' or 'max', got '$FISHARCHY_MODE'"
unset FISHARCHY_PERFORMANCE
export FISHARCHY_MODE

# KDE Plasma is the only desktop.
FISHARCHY_DESKTOP=kde
export FISHARCHY_DESKTOP

# Universal build: one ISO for NVIDIA, AMD and Intel machines.
export FISHARCHY_KEEP_HARDWARE=${FISHARCHY_KEEP_HARDWARE:-1}

# ---- pinned versions --------------------------------------------------------
versions=$root/iso/versions.env
[[ -f $versions ]] || die "missing $versions"
env_iso_commit=${OMARCHY_ISO_COMMIT:-}
# shellcheck source=iso/versions.env
source "$versions"
# An OMARCHY_ISO_COMMIT set in the environment still wins (for testing).
OMARCHY_ISO_COMMIT=${env_iso_commit:-${OMARCHY_ISO_COMMIT:?iso/versions.env must set OMARCHY_ISO_COMMIT}}

# ---- required tools, with a hint for each ----------------------------------
need() {
  local cmd=$1 hint=$2
  command -v "$cmd" >/dev/null 2>&1 || die "missing required command '$cmd' ($hint)"
}
need git "install git"
need makepkg "run this on Arch Linux; makepkg is part of pacman"
need docker "install docker and add yourself to the docker group"
need bsdtar "install libarchive"
need python3 "install python"
(( EUID != 0 )) || die "makepkg refuses to run as root; run as a normal user"
docker info >/dev/null 2>&1 ||
  die "cannot talk to the Docker daemon (is it running? are you in the docker group?)"

mkdir -p "$work" "$pkgdest"

# ---- disk space -------------------------------------------------------------
free_gb=$(df -P -BG "$work" | awk 'NR==2 {gsub(/G/, "", $4); print $4}')
if [[ $free_gb =~ ^[0-9]+$ ]] && (( free_gb < min_free_gb )); then
  echo "build-fisharchy: WARNING: only ${free_gb} GB free in $work; the build wants about ${min_free_gb} GB." >&2
  echo "build-fisharchy: it may fail part way through. Free some space or set FISHARCHY_WORK_DIR." >&2
fi

# ---- private repositories: fail early and clearly --------------------------
private_repos=(omarchy-boot-branding)
for repo in "${private_repos[@]}"; do
  if ! GIT_TERMINAL_PROMPT=0 git ls-remote --exit-code \
      "https://github.com/$GH_OWNER/$repo.git" HEAD >/dev/null 2>&1; then
    cat >&2 <<EOF
build-fisharchy: cannot clone https://github.com/$GH_OWNER/$repo.git
  The FISHARCHY boot-branding package repository is private, so only the repository
  owner can rebuild this image. Everyone else: use the released ISO.
  Owner: run 'gh auth login && gh auth setup-git' and try again.
EOF
    exit 1
  fi
done

# ---- lean warning -----------------------------------------------------------
if [[ $FISHARCHY_KEEP_HARDWARE == 0 ]]; then
  cat >&2 <<'EOF'

################################################################
#  LEAN BUILD: this ISO is for THIS PC ONLY.                   #
#  It leaves out firmware and drivers for other hardware and   #
#  may not boot, or may have no working Wi-Fi, Bluetooth or    #
#  graphics, on any other machine. Do not publish it.          #
#  Use --universal (the default) for an ISO anyone can use.    #
################################################################

EOF
fi

# ---- helpers ---------------------------------------------------------------
is_sha() { [[ $1 =~ ^[0-9a-f]{40}$ ]]; }

# Check out <ref> in <dir> and print the commit; refuse anything unresolvable.
checkout_ref() {
  local dir=$1 ref=$2 sha
  git -C "$dir" fetch --quiet --tags origin ||
    die "cannot fetch updates for $dir (network or access problem)"
  sha=$(git -C "$dir" rev-parse --verify --quiet "origin/$ref^{commit}" ||
        git -C "$dir" rev-parse --verify --quiet "$ref^{commit}") || sha=
  if [[ -z $sha && ( $ref == main || $ref == master ) ]]; then
    # The repository's default branch has another name (main vs master).
    git -C "$dir" remote set-head origin --auto >/dev/null 2>&1 || true
    sha=$(git -C "$dir" rev-parse --verify --quiet "origin/HEAD^{commit}") || sha=
    [[ -n $sha ]] && echo "build-fisharchy: WARNING: '$ref' not found in ${dir##*/}; using its default branch instead" >&2
  fi
  if [[ -z $sha ]]; then
    echo "build-fisharchy: branches/tags available in ${dir##*/}:" >&2
    git -C "$dir" branch -a --list >&2 || true
    git -C "$dir" tag --list | head -10 >&2 || true
    die "ref '$ref' not found in $dir; set the right branch or commit in iso/versions.env"
  fi
  git -C "$dir" checkout --quiet --detach --force "$sha"
  git -C "$dir" reset --quiet --hard "$sha"
  git -C "$dir" clean -fdxq
  printf '%s\n' "$sha"
}

clone_at() {
  local url=$1 dir=$2 ref=$3
  if [[ ! -d $dir/.git ]]; then
    rm -rf -- "$dir"
    GIT_TERMINAL_PROMPT=0 git clone --quiet "$url" "$dir" || die "cannot clone $url"
  fi
  is_sha "$ref" || echo "build-fisharchy: WARNING: '$ref' for ${dir##*/} is not a commit SHA; this build is not reproducible" >&2
  checkout_ref "$dir" "$ref"
}

build_package() {
  local dir=$1
  printf '\n==> Building %s\n' "${dir##*/}"
  (
    cd -- "$dir"
    PKGDEST="$pkgdest" makepkg -f --nodeps --noconfirm
  ) || die "makepkg failed for ${dir##*/}"
}

# ---- the omarchy-iso builder, reset to a clean pinned tree -----------------
build_date=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# A cached builder or package mirror from a different mode causes red installer
# failure screens, so clear it when the hardware mode or security mode changes.
mode_file=$work/.fisharchy-mode
mode_key="$FISHARCHY_KEEP_HARDWARE-$FISHARCHY_MODE"
if [[ -f $mode_file && $(cat "$mode_file") != "$mode_key" ]]; then
  echo "==> Build mode changed; clearing cached ISO build state"
  rm -rf -- "$builder/release" "$builder/.cache" "$builder/custom-packages"
  mapfile -t stale < <(docker volume ls -q 2>/dev/null | grep -i omarchy || true)
  if (( ${#stale[@]} > 0 )); then
    echo "==> Removing Docker volumes: ${stale[*]}"
    docker volume rm "${stale[@]}" >/dev/null 2>&1 || true
  fi
fi
echo "$mode_key" >"$mode_file"

if [[ ! -d $builder/.git ]]; then
  git clone --quiet https://github.com/omacom-io/omarchy-iso.git "$builder" ||
    die "cannot clone omacom-io/omarchy-iso"
fi
git -C "$builder" fetch --quiet origin || die "cannot fetch omacom-io/omarchy-iso"
git -C "$builder" cat-file -e "${OMARCHY_ISO_COMMIT}^{commit}" 2>/dev/null ||
  die "pinned omarchy-iso commit $OMARCHY_ISO_COMMIT cannot be fetched (was it removed upstream? update iso/versions.env and iso/fisharchy.patch)"
git -C "$builder" checkout --quiet --force "$OMARCHY_ISO_COMMIT"
# A leftover patched tree causes a false 'builder has diverged' error, so reset
# it fully. Keep the package cache and finished ISOs so rebuilds stay fast.
git -C "$builder" reset --quiet --hard "$OMARCHY_ISO_COMMIT"
git -C "$builder" clean -fdxq -e /.cache -e /release
git -C "$builder" submodule update --init --recursive --jobs=8 ||
  die "omarchy-iso submodule update failed"

if ! apply_out=$(git -C "$builder" apply --check "$root/iso/fisharchy.patch" 2>&1); then
  printf '%s\n' "$apply_out" >&2
  die "iso/fisharchy.patch no longer applies to omarchy-iso@${OMARCHY_ISO_COMMIT:0:12}; the patch must be updated"
fi
git -C "$builder" apply "$root/iso/fisharchy.patch"
echo "==> Applied iso/fisharchy.patch"


# ---- the custom packages ----------------------------------------------------
sha_iso=$OMARCHY_ISO_COMMIT
sha_boot=$(clone_at "https://github.com/$GH_OWNER/omarchy-boot-branding.git" "$work/omarchy-boot-branding" "$BOOT_BRANDING_REF")

FISHARCHY_BUILD_DATE=$build_date
FISHARCHY_PINS="omarchy-iso=${sha_iso:0:12} boot-branding=${sha_boot:0:12}"
export FISHARCHY_BUILD_DATE FISHARCHY_PINS

cat <<EOF

================ FISHARCHY build ================
 date      : $build_date
 mode      : $FISHARCHY_MODE $( [[ $FISHARCHY_MODE == safe ]] && echo '(CPU mitigations ON)' || echo '(CPU mitigations OFF - Max Performance)' )
 hardware  : $( [[ $FISHARCHY_KEEP_HARDWARE == 1 ]] && echo 'universal' || echo 'LEAN (this PC only)' )
 desktop   : KDE Plasma
 pins      : $FISHARCHY_PINS
=================================================

EOF

# Stale archives of older versions make the builder fail with "multiple custom
# builds", so start every build from empty package directories.
rm -f -- "$pkgdest"/*.pkg.tar.*
rm -rf -- "$custom"

build_package "$work/omarchy-boot-branding"

build_package "$root/packages/omarchy-no-preinstalls"
build_package "$root/packages/fisharchy-kde-theme"

mkdir -p "$custom"
for archive in "$pkgdest"/*.pkg.tar.zst; do
  [[ $archive == *-debug-* ]] && continue
  cp -f -- "$archive" "$custom/"
done
ls -1 "$custom"

# ---- the ISO ---------------------------------------------------------------
cd -- "$builder"
./bin/omarchy-iso-make --no-boot-offer --keep-pkg-cache

shopt -s nullglob
isos=("$builder"/release/*.iso)
(( ${#isos[@]} > 0 )) || die "the build finished but produced no ISO in $builder/release"

# Checksums next to the ISO(s); tools/publish-release.sh extends this file with
# the split parts.
(cd -- "$builder/release" && sha256sum -- *.iso >SHA256SUMS)

printf '\nFISHARCHY ISO(s):\n'
ls -lh "${isos[@]}"
printf '\nChecksums written to %s/release/SHA256SUMS\n' "$builder"

if (( record_pins )); then
  python3 - "$versions" "$sha_boot" <<'PY'
import re, sys
path, boot = sys.argv[1:]
vals = {"BOOT_BRANDING_REF": boot}
text = open(path).read()
for key, val in vals.items():
    if not val:
        continue
    text = re.sub(rf"^{key}=.*$", f"{key}={val}", text, flags=re.M)
open(path, "w").write(text)
PY
  echo "Recorded the built commits in $versions"
fi
