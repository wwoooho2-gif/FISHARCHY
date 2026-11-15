# FISHARCHY roadmap

Phase 1 (done, in this repository): safe-by-default modes, performance and stability layer, release
integrity, pinned inputs, private-repo checks, lean warnings, cleanups.

Everything below is **not built yet**. It needs the upstream `omarchy-iso` / Omarchy source at the
pinned commit and real test builds (a VM or hardware), which could not be done in the session that
produced Phase 1. Nothing here has been verified.

## Not verified yet (Phase 1 items to test on a real build)

- `iso/fisharchy.patch` applies to omarchy-iso `38d8d05` after the edits (the patch parses, but was not applied to the real tree).
- `fisharchy-tuning` installs from the offline mirror (dependency `zram-generator` was added to `builder/image.packages`; if the mirror prune drops it, add it to the install lists instead).
- `fisharchy-mode` finds `limine-update` on Omarchy (`/etc/kernel/cmdline` and the Limine drop-in are written; boot entries are regenerated only if `limine-update` exists).
- `systemd-oomd` is enabled and active on the installed system; `ManagedOOMPreference=avoid` on the compositor unit is best effort.
- `tcp_bbr` is available in the Omarchy kernel; `bfq` is built or loadable.
- Run on the real machine: `systemd-analyze`, `zramctl`, `sysctl vm.max_map_count`, `oomctl`, `fisharchy-bench`.

## Phase 2 (in suggested order)

| # | Work | Honest effort | Notes |
|---|---|---|---|
| 1 | linux-zen as an extra kernel; `linux-omarchy` becomes the fallback boot entry | Medium | Omarchy ships `linux-omarchy`, not stock `linux`. NVIDIA DKMS needs `linux-zen-headers` in the offline mirror. A custom x86-64-v3 kernel is high effort (hours per build, own repo): ask before doing it. |
| 2 | Gaming bundle (Steam, lib32 Vulkan for all GPUs, Gamemode, MangoHud, gamescope, ProtonUp) | Medium | Package choices are easy; large offline-mirror growth, so make it an optional bundle. |
| 3 | Hyprland game defaults (VRR, tearing, no blur/animation in fullscreen) via window rules | Low-medium | Needs Omarchy's Hyprland config layout from the pinned commit. |
| 4 | Installer menus: performance mode and animated wallpaper | Medium-high | Needs the real installer code. Fallback if upstream is too fragile: a small FISHARCHY pre-install step that writes a choice file. |
| 5 | Animated wallpaper switch (`fisharchy-wallpaper`) | Medium | |
| 6 | Welcome app, one-click update with snapshots, `fisharchy-backup` / `fisharchy-restore` | High | Backup excludes passwords, SSH keys and browser data unless ticked. |
| 7 | Graphical guided installer, software store, "Install in 5 minutes" with screenshots | Highest | Omarchy's installer is a terminal flow, not a graphical one; a Calamares-style installer is a separate large project. |


## What Omarchy likely already does (to confirm against the pinned source)

btrfs root with snapshots, Limine bootloader, automatic GPU driver selection, Wi-Fi setup in the live
ISO, Walker launcher, Hyprland keybindings and its own theme system. Likely **not** present: a
graphical installer, Flathub/software store, backup/restore.
