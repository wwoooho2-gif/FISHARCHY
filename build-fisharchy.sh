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

# Replace the boot/unlock-screen logo image in the omarchy-boot-branding checkout ($1) with the FISHARCHY one.
# Matches PNGs named like a logo (or the Plymouth wordmark); prints each file, warns if none are found.
replace_boot_logo() {
  local dir=$1 logo=$2 f n=0
  while IFS= read -r f; do
    cp -f -- "$logo" "$f"; echo "    boot logo -> ${f#"$dir"/}"; n=$((n + 1))
  done < <(find "$dir" -type f -iname '*.png' \( -iname '*logo*' -o -iname '*wordmark*' -o -iname 'watermark*' \) -not -path '*/.git/*' 2>/dev/null)
  (( n > 0 )) || echo "WARNING: no logo PNG found in $dir; the boot screen may still say OMARCHY. Send me the file list of that repo." >&2
}

# Rebrand the installer splash (logo + tagline) and make Wi-Fi setup part of the install flow.
# Works on the cloned builder tree ($1) without fixed line numbers: it searches for the logo and the
# launcher by content, prints every file it changes, and warns if it finds nothing.
rebrand_installer() {
  local tree=$1 f changed=0 logo_changed=0
  local tagline='Beautiful, Fun & Agentic Linux by DHH'
  local new_tagline='A clean, neon, Fish-themed Linux'
  local -a skip=(-not -path '*/.git/*' -not -path '*/.cache/*' -not -path '*/release/*' -not -path '*/test/*')

  # 1) Logo: any text file that is block-character art named like a logo is replaced with ours.
  while IFS= read -r f; do
    grep -qIE '[█▀▄▌▐]' "$f" 2>/dev/null || continue
    cp -f -- "$root/iso/fisharchy-logo.txt" "$f"
    echo "    logo -> ${f#"$tree"/}"; logo_changed=$((logo_changed + 1))
  done < <(find "$tree" -type f -iname '*logo*' "${skip[@]}" 2>/dev/null)

  # 2) Tagline + the word OMARCHY in any text file that carries the tagline (the splash script/text).
  while IFS= read -r f; do
    sed -i -e "s/$tagline/$new_tagline/g" -e 's/\bOMARCHY\b/FISHARCHY/g' "$f"
    echo "    splash text -> ${f#"$tree"/}"; changed=$((changed + 1))
  done < <(grep -rIl --exclude-dir=.git --exclude-dir=.cache --exclude-dir=release -F "$tagline" "$tree" 2>/dev/null)

  # 3) Wi-Fi step: call fisharchy-wifi just before the "Press Return" prompt, but only if the file is a
  #    shell script and still parses afterwards (otherwise the edit is undone).
  local launcher
  launcher=$(grep -rIl --exclude-dir=.git --exclude-dir=.cache --exclude-dir=release -F 'Press Return to Start Install' "$tree" 2>/dev/null | head -1)
  if [[ -n $launcher ]] && head -1 "$launcher" | grep -q 'bash\|sh' && ! grep -q 'fisharchy-wifi' "$launcher"; then
    cp -f -- "$launcher" "$launcher.fisharchy-bak"
    sed -i '0,/Press Return to Start Install/s//&/;0,/^.*Press Return to Start Install.*$/s//[[ -x \/usr\/local\/bin\/fisharchy-wifi ]] \&\& \/usr\/local\/bin\/fisharchy-wifi || true\n&/' "$launcher"
    if bash -n "$launcher" 2>/dev/null; then
      rm -f -- "$launcher.fisharchy-bak"
      echo "    wifi step -> ${launcher#"$tree"/}"
    else
      mv -f -- "$launcher.fisharchy-bak" "$launcher"
      echo "WARNING: could not safely add the Wi-Fi step to ${launcher#"$tree"/}" >&2
    fi
  else
    echo "WARNING: no editable installer launcher found; Wi-Fi step NOT added by FISHARCHY (relying on the builder's own)" >&2
  fi

  # Put the helper on the live ISO (/usr/local/bin/fisharchy-wifi). /configs is mounted in the build container.
  install -Dm755 "$root/iso/fisharchy-wifi" "$tree/configs/fisharchy-wifi"
  local iso_script=$tree/builder/build-iso.sh
  local wifi_anchor='mkdir -p "$build_cache_dir/airootfs/usr/share/omarchy-iso"'
  if [[ -f $iso_script ]] && ! grep -q 'fisharchy-wifi' "$iso_script"; then
    if [[ $(grep -cFx -- "$wifi_anchor" "$iso_script") == 1 ]]; then
      sed -i "\|^mkdir -p \"\$build_cache_dir/airootfs/usr/share/omarchy-iso\"\$|a install -Dm755 /configs/fisharchy-wifi \"\$build_cache_dir/airootfs/usr/local/bin/fisharchy-wifi\"" "$iso_script"
      echo "    wifi helper -> builder/build-iso.sh"
    else
      echo "WARNING: anchor for fisharchy-wifi not found in builder/build-iso.sh; the Wi-Fi helper is NOT in this ISO" >&2
    fi
  fi

  (( logo_changed + changed > 0 )) || echo "WARNING: found no installer logo or tagline to rebrand in $tree; the splash may still say OMARCHY" >&2
}

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
  --netinstall         build a SMALL ISO (about 1.4 GiB) named fisharchy.iso that installs over the
                       network and asks for Wi-Fi during install. It installs stock Omarchy; run
                       tools/fisharchy-postinstall afterwards to add FISHARCHY. Unofficial builder
                       (see iso/versions.env). Needs Docker and git only. The other flags are ignored.
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
netinstall=0
for arg in "$@"; do
  case $arg in
    --netinstall) netinstall=1 ;;
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
(( netinstall )) || need makepkg "Run this on Arch Linux or an Arch container (pacman -S base-devel)."
need docker "Install Docker and start it (pacman -S docker; sudo systemctl enable --now docker)."
(( netinstall )) || need bsdtar "Install libarchive (pacman -S libarchive)."
docker info >/dev/null 2>&1 || die "Docker is installed but not usable. Start it and add yourself to the docker group (sudo usermod -aG docker \$USER, then log in again)."

# --netinstall: build the small network-install ISO from the pinned third-party builder branch and stop.
if (( netinstall )); then
  nwork=${FISHARCHY_WORK_DIR:-$root/build-work}/netinstall
  nbuilder=$nwork/omarchy-iso
  mkdir -p "$nwork"
  free_gb=$(df -Pk "$nwork" | awk 'NR==2 {print int($4/1024/1024)}')
  (( free_gb >= 10 )) || echo "WARNING: only ${free_gb} GB free in $nwork; the build may fail." >&2
  cat >&2 <<'NOTE'
==> NETINSTALL build
    * UNOFFICIAL: this uses a third-party branch of the Omarchy ISO builder (pinned in iso/versions.env).
    * The result installs STOCK Omarchy over the network. FISHARCHY is added afterwards with
      tools/fisharchy-postinstall. Only the installer splash branding and the Wi-Fi step come from FISHARCHY's patch.
    * The install needs a working internet connection (Ethernet, or Wi-Fi via the install step).
NOTE
  if [[ ! -d $nbuilder/.git ]]; then
    git clone --quiet "$NETINSTALL_ISO_REPO" "$nbuilder" || die "cannot clone $NETINSTALL_ISO_REPO"
  fi
  git -C "$nbuilder" fetch --quiet origin || die "cannot fetch $NETINSTALL_ISO_REPO"
  git -C "$nbuilder" cat-file -e "${NETINSTALL_ISO_COMMIT}^{commit}" 2>/dev/null ||
    die "pinned netinstall commit $NETINSTALL_ISO_COMMIT is not in $NETINSTALL_ISO_REPO (the branch may have been deleted or rewritten)."
  git -C "$nbuilder" reset --hard --quiet
  git -C "$nbuilder" clean -fdxq -e .cache -e release
  git -C "$nbuilder" checkout --quiet --force "$NETINSTALL_ISO_COMMIT"
  git -C "$nbuilder" submodule update --init --recursive --jobs=8
  echo "==> Rebranding the installer splash and adding the Wi-Fi step"
  rebrand_installer "$nbuilder"
  echo "==> Building the netinstall ISO (this downloads several GB the first time)"
  rm -f -- "$nbuilder"/release/*.iso
  (cd -- "$nbuilder" && ./bin/omarchy-iso-make --netinstall --keep-pkg-cache --no-boot-offer)
  built=$(ls -1t "$nbuilder"/release/*.iso 2>/dev/null | head -1)
  [[ -n $built ]] || die "the build finished but no ISO was found in $nbuilder/release"
  # Moved out of release/ so publish-release.sh never mistakes it for the full FISHARCHY ISO.
  mv -f -- "$built" "$root/fisharchy.iso"
  (cd -- "$root" && sha256sum fisharchy.iso >fisharchy.iso.sha256)
  printf '\nNetinstall ISO ready:\n'
  ls -lh "$root/fisharchy.iso"
  cat <<'NEXT'

Next:
  1. Write fisharchy.iso to a USB stick (check lsblk first):
       sudo dd if=fisharchy.iso of=/dev/sdX bs=16M status=progress oflag=sync
  2. Boot it. After you pick the keyboard layout, the installer asks you to connect to Wi-Fi
     (skipped on Ethernet), then installs Omarchy over the network.
  3. On the installed system, add FISHARCHY:
       bash tools/fisharchy-postinstall
NEXT
  exit 0
fi

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
  # Resolve the ref to a commit first (branch, tag or SHA); HEAD means the repo's default branch.
  local candidate target=""
  for candidate in "origin/$ref" "$ref" "origin/HEAD"; do
    [[ $candidate == origin/HEAD && $ref != HEAD && $ref != main && $ref != master ]] && continue
    if target=$(git -C "$dir" rev-parse --verify --quiet "${candidate}^{commit}"); then
      break
    fi
    target=""
  done
  [[ -n $target ]] || die "ref '$ref' not found in $url"
  git -C "$dir" checkout --quiet --force --detach "$target"
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

# Rebrand the boot menus: the live ISO's GRUB/syslinux/systemd-boot entries and the installed
# system's os-release (Limine takes its entry names from it). Only user-visible text is touched:
# menu titles, ISO label, "Omarchy" in os-release NAME/PRETTY_NAME. Package, path and command names
# (omarchy-*) stay as they are, because the rest of the system depends on them.
rebrand_menus() {
  local file changed=0
  while IFS= read -r file; do
    # menuentry/title/label/MENU TITLE lines, and iso_* fields in profiledef.sh
    if grep -qiE 'omarchy' "$file" &&
       sed -i -E \
         -e '/(menuentry|^[[:space:]]*(title|MENU TITLE|MENU LABEL|LABEL)[[:space:]]|iso_(name|label|publisher|application)=)/ s/Omarchy/FISHARCHY/g; /(menuentry|^[[:space:]]*(title|MENU TITLE|MENU LABEL)[[:space:]]|iso_(label|publisher|application)=)/ s/OMARCHY/FISHARCHY/g' \
         "$file" && ! cmp -s "$file" <(git -C "$builder" show "HEAD:${file#"$builder"/}" 2>/dev/null); then
      echo "    rebranded ${file#"$builder"/}"
      changed=$((changed + 1))
    fi
  done < <(find "$builder/configs" "$builder/builder" -type f \
             \( -name '*.cfg' -o -name '*.conf' -o -name 'profiledef.sh' -o -path '*syslinux*' -o -path '*efiboot*' -o -path '*grub*' \) 2>/dev/null)
  if (( changed == 0 )); then
    echo "WARNING: found no boot menu text to rebrand in the omarchy-iso tree; the ISO menu may still say Omarchy" >&2
  else
    echo "==> Rebranded $changed boot menu file(s) to FISHARCHY"
  fi
}
rebrand_menus
rebrand_installer "$builder"

# Installed system: make os-release say FISHARCHY. Done in the root image build so Limine's entries,
# the login screen and fastfetch pick it up. NAME/PRETTY_NAME only; ID and ID_LIKE stay untouched.
root_image_script="$builder/builder/build-root-image.sh"
if [[ -f $root_image_script ]] && ! grep -q 'FISHARCHY_OSRELEASE' "$root_image_script"; then
  cat >>"$root_image_script" <<'OSREL'

# FISHARCHY_OSRELEASE: rebrand the installed system's name (menus read NAME/PRETTY_NAME)
for osrel in "$root/usr/lib/os-release" "$root/etc/os-release"; do
  [[ -f $osrel && ! -L $osrel ]] || continue
  sed -i -E 's/^(NAME|PRETTY_NAME)=.*/\1="FISHARCHY"/' "$osrel"
done
OSREL
  echo "==> Added os-release rebrand to build-root-image.sh"
fi

branding_sha=$(checkout_ref "https://github.com/$GH_OWNER/omarchy-boot-branding.git" "$work/omarchy-boot-branding" "$BRANDING_REF")
replace_boot_logo "$work/omarchy-boot-branding" "$root/iso/fisharchy-boot-logo.png"
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

# Drop stale custom archives from the cached offline mirror (kept by --keep-pkg-cache) so only the
# fresh builds remain; otherwise the patched builder fails with "multiple custom builds found".
if [[ -d $builder/.cache ]]; then
  find "$builder/.cache" -type f \( \
    -name 'omarchy-boot-branding-*.pkg.tar.*' -o -name 'omarchy-fish-theme-*.pkg.tar.*' -o \
    -name 'omarchy-fishylayout-*.pkg.tar.*' -o -name 'omarchy-radio-atlas-*.pkg.tar.*' -o \
    -name 'omarchy-no-preinstalls-*.pkg.tar.*' -o -name 'fisharchy-tuning-*.pkg.tar.*' \) \
    -delete 2>/dev/null || true
fi

cd -- "$builder"
./bin/omarchy-iso-make --no-boot-offer --keep-pkg-cache

# Keep exactly one ISO: move the builder's output to fisharchy.iso next to this script (same name and
# layout as --netinstall) so the builder's omarchy-*.iso name does not stay behind in release/.
newest_iso=$(ls -1t "$builder"/release/*.iso 2>/dev/null | head -1)
[[ -n $newest_iso ]] || die "build finished but no ISO was found in $builder/release"
mv -f -- "$newest_iso" "$root/fisharchy.iso"
# Remove every leftover builder ISO (old omarchy-*.iso builds) and its checksum file; fisharchy.iso is kept.
rm -f -- "$builder"/release/*.iso "$builder"/release/SHA256SUMS
(cd -- "$root" && sha256sum fisharchy.iso >fisharchy.iso.sha256)
printf '\nFISHARCHY ISO:\n'
ls -lh "$root/fisharchy.iso"
echo "Wrote $root/fisharchy.iso.sha256"
[[ $hw_name == lean ]] && echo "REMINDER: this is a LEAN ISO for this PC only. Do not share it." >&2
exit 0
