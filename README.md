# FISHARCHY

A custom [Omarchy](https://omarchy.org/) ISO: clean and neon, with **KDE
Plasma** as the only desktop (Hyprland is removed).

The finished image is published in this repository's **Releases** as
`FISHARCHY.iso` (split into `FISHARCHY.iso.part-*` when it exceeds GitHub's
2 GiB per-asset limit) together with `SHA256SUMS`. Download every part and
`SHA256SUMS` into one directory and run `tools/reassemble-iso.sh` there. It
verifies everything for you (see *Verify your download*).

```bash
./tools/reassemble-iso.sh ~/Downloads ~/Downloads/FISHARCHY.iso
```

## What is baked in

| Component | What it does |
|---|---|
| **Neon boot branding** | Plymouth splash and SDDM login screen using the `#0d1a3d` / `#19e6ff` wordmark |
| **KDE Plasma** | Plasma (Wayland) is the only desktop. SDDM logs in to it, and Omarchy's Hyprland packages are filtered out of the install lists |
| **FISHARCHY Neon theme** | `fisharchy-kde-theme`: a navy/cyan color scheme (`#0d1a3d` / `#19e6ff`) set as the default for every user, plus the FISHARCHY Reef wallpaper applied at first login |
| **No preinstalls** | Omarchy's preinstalled desktop apps, web apps, TUI wrappers, and mise tools are removed before the image is built, and the `preinstalls-removed` opt-out is recorded |
| **Universal image** | One ISO for NVIDIA and non-NVIDIA machines: every GPU driver and firmware family stays in, and the installer detects the hardware and picks the driver at install time. `FISHARCHY_KEEP_HARDWARE=0` builds the single-PC lean image instead (T2 kernel, legacy NVIDIA, Surface firmware, other radios/GPUs, unused runtimes and unused firmware left out; about 1.5 GB smaller) |

The result is a fresh Omarchy install that boots branded and lands on KDE
Plasma.

> **Experimental.** Omarchy itself is built around Hyprland. Some of its own
> install steps and packages may still expect it, so test the ISO in a VM
> before writing it to a USB stick. If an install step fails, keep the log.

## Packages

- [`omarchy-boot-branding`](https://github.com/wwoooho2-gif/omarchy-boot-branding) (private repository)
- `packages/omarchy-no-preinstalls` - first-boot cleanup for the preinstalled apps
- `packages/fisharchy-kde-theme` - the KDE color scheme, reef wallpaper and the once-per-user first-login script. It also turns KDE Wallet off by default (`/etc/xdg/kwalletrc`). Re-apply it any time with `/usr/share/fisharchy/fisharchy-theme-apply --force`

## Verify your download

Every release ships a `SHA256SUMS` file listing the ISO and every part. Put it
in the same directory as the downloaded files.

Split release (parts):

```bash
cd ~/Downloads
grep ' FISHARCHY.iso.part-' SHA256SUMS | sha256sum -c -   # check the parts
./tools/reassemble-iso.sh ~/Downloads ~/Downloads/FISHARCHY.iso   # re-checks parts, joins, checks the ISO
```

Single-file release:

```bash
cd ~/Downloads
sha256sum -c SHA256SUMS --ignore-missing
```

Every line must say `OK`. If any line says `FAILED`, download that file again;
do not write it to a USB stick.

## Write the ISO to USB

**This erases the target device.** Find the right one first:

```bash
lsblk -o NAME,SIZE,MODEL,TRAN,MOUNTPOINTS
```

Your USB stick is the entry whose size and model match it (usually `TRAN`
`usb`). Make sure nothing on it is mounted and that you are NOT picking your
system disk. Then, with the whole device (for example `/dev/sdb`, not
`/dev/sdb1`):

```bash
sudo dd if=~/Downloads/FISHARCHY.iso of=/dev/sdX bs=16M status=progress oflag=sync
```

Or open the ISO in [Ventoy](https://www.ventoy.net/) if the stick already uses it.

## Security mode: Safe or Max Performance

| Mode | Kernel command line | Meaning |
|---|---|---|
| **Safe** (default) | `nowatchdog` | CPU mitigations (Spectre, Meltdown, L1TF, SRSO) stay **on**. |
| **Max Performance** | `nowatchdog mitigations=off split_lock_detect=off` | Mitigations and split-lock traps **off**. A few percent faster on syscall-heavy work; the machine is exposed to CPU side-channel attacks. Only choose this if you accept that. |

The mode is chosen when the ISO is built and applies to the live ISO and to
every system installed from it. It is recorded in `/etc/fisharchy-release`.

```bash
./build-fisharchy.sh                    # Safe (default)
./build-fisharchy.sh --max-performance  # or: FISHARCHY_MODE=max ./build-fisharchy.sh
```

Not implemented yet (planned): `fisharchy-mode` to switch an installed system
between the two, and the same choice in the installer menu.

Migration note: older builds were Max Performance by default and used
`FISHARCHY_PERFORMANCE` (where `0` meant mitigations on). That variable and
`--hardened` still work but are deprecated: `0` maps to Safe, `1` to Max.

## Rebuilding

Rebuilding needs access to the **private** `omarchy-boot-branding`
repository, so only the repository owner can rebuild the image. For everyone else the released ISO is
the supported way to use FISHARCHY. If the repositories cannot be cloned the
script stops straight away with a message saying so.

```bash
gh auth login && gh auth setup-git     # owner only
./build-fisharchy.sh
```

Requirements: Arch Linux with `git`, `base-devel` (`makepkg`), `libarchive`
(`bsdtar`), `python` and a running Docker daemon you can use without root.
Keep roughly **20 GB** free; the script warns if there is less.

Inputs are pinned in `iso/versions.env`: the `omarchy-iso` commit and the
boot-branding package. Branch names work but make the
build non-reproducible (the build warns). After a good build:

```bash
./build-fisharchy.sh --record-pins     # writes the exact built commits into iso/versions.env
```

The build fails early with a clear message if the pinned `omarchy-iso` commit
cannot be fetched or `iso/fisharchy.patch` no longer applies. The cached
builder tree is reset and cleaned before every patch, so a leftover patched
tree can no longer cause a false "builder has diverged" error. Each build
prints, and records in `/etc/fisharchy-release`, the pinned versions, build
date, mode and desktop.

`build-fisharchy.sh --help` lists every option.

### Lean build: this PC only

```bash
./build-fisharchy.sh --lean
```

> **Warning:** the lean ISO is for the exact PC it was built on. It removes
> firmware and drivers for other hardware and **may not boot, or may have no
> working Wi-Fi, Bluetooth or graphics, on any other machine.** Never publish
> or share a lean ISO. The default `--universal` build is the one for everyone.

The lean build leaves out about 1.5 GB: the T2 kernel, legacy NVIDIA, Surface
and laptop-vendor packages, other GPUs and radios, mise/dotnet/ruby, and all
firmware except Intel Wi-Fi/Bluetooth, Realtek Ethernet, NVIDIA GPU and CPU
microcode. Dropped dev runtimes come back with
`sudo pacman -S mise dotnet-runtime ruby`.

### What `iso/fisharchy.patch` does

1. Copies the locally built archives into the offline mirror and keeps them
   through the prune/index step.
2. Adds them and the KDE Plasma packages to `builder/image.packages`, so they
   are installed in the root image that fresh installs are written from, and
   writes an SDDM config that starts the Plasma session.
3. Filters Hyprland and Omarchy's preinstall packages out of the shipped install lists (and,
   with `--lean`, the hardware and tool packages listed above).
4. Sets the kernel command line for the chosen mode (see *Security mode*) and
   writes `/etc/fisharchy-release`.
5. Trims things no install needs: theme intro videos, GUI help, docs and info pages,
   non-English locales, Chromium and Qt translations; the man database is
   generated at build time. About 120 MB less to
   write at install time.
6. Uses `ParallelDownloads = 20` inside the build and `10` in the pacman
   configs of installed systems.

Most of the remaining wall-clock boot time is firmware POST (BIOS "Fast Boot",
memory training) and the LUKS passphrase, not the image.

First-boot cleanup comes from an `/etc/skel` hook installed by
`omarchy-no-preinstalls` (`05-remove-preinstalls`). It is safe to run twice.

## Troubleshooting

**Black screen after the login screen.**
Switch to a text console (`Ctrl+Alt+F3`), log in and run
`journalctl -b -p warning --no-pager | tail -60`. Check the GPU with
`lspci -nnk | grep -EA3 'VGA|3D'`. A leftover Hyprland session in
`/etc/sddm.conf.d/` can override the Plasma one; the KDE image ships
`zz-fisharchy-kde.conf`, which should win.

**The Docker build fails.**
Run `docker info`; if it errors, start Docker (`sudo systemctl start docker`)
and add yourself to the `docker` group (log out and in afterwards). Check free
space (`df -h .`, about 20 GB needed). If the failure is "builder has
diverged" or the patch not applying, the pinned commit and `iso/fisharchy.patch`
are out of step; the script says which. After a mode change the script clears
its caches itself. Re-run with the output saved (`./build-fisharchy.sh 2>&1 |
tee build.log`) and read the first `ERROR` line, not the last.

**The ISO does not boot from USB.**
Re-verify the download (*Verify your download*) and re-write the stick with
`dd` after checking `lsblk`; a stick written to a partition (`/dev/sdb1`)
will not boot. In the firmware setup pick the USB entry marked UEFI. If Secure
Boot is on and it is refused, turn Secure Boot off for the install. Try
another USB port (a USB 2 port is often more reliable) or another stick.

**The installer does not detect the GPU.**
The installer picks the driver from the hardware it sees, and the universal
ISO contains every driver family. First check what the live system sees:
`lspci -nnk | grep -EA3 'VGA|3D'`. On a hybrid laptop both GPUs should show.
If the GPU is missing there, update the firmware (BIOS) and check whether the
BIOS has a "hybrid" or "discrete only" GPU option. If it shows up but the
installed system has no graphics driver, keep the installer log and open an
issue with the `lspci` output. Do not use a `--lean` ISO on a different PC; it
deliberately leaves GPU drivers out.

## Licensing

- The build scripts and recipes in this repository are **MIT** (see `LICENSE`).
- **Omarchy** itself keeps its own license, found in its repository.
- `omarchy-boot-branding` is included in the ISO under the licence stated in
  its own repository.
  <!-- TODO (owner): if that repository has no LICENSE file, state its
  licence here, for example: "All rights reserved" or "MIT". -->
- KDE Plasma and its applications keep their own licenses (mostly GPL/LGPL).
