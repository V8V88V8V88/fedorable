# Fedorable

Bash script for Fedora maintenance. Calls dnf, journalctl, flatpak, fstrim, nothing else. No daemons, no telemetry.



---

## Install

```bash
git clone https://github.com/V8V88V8V88/fedorable.git
cd fedorable
chmod +x fedorable.sh
```

One file, `fedorable.sh`. No pip, no packages. You control what runs.

## Run

```bash
sudo ./fedorable.sh
```

Menu at start: minimal (update + reset failed units), recommended (common cleanups), or advanced (pick each task). Nothing runs until you choose.

## Modes

| Mode | What it does |
|------|--------------|
| Minimal | Update + reset failed systemd units |
| Recommended | Update + autoremove, DNF cache, old kernels, journal, temp files, GRUB, Flatpak, failed units, TRIM, coredumps |
| Advanced | Turn each task on/off yourself |

## Flags

Skip the menu with flags:

```bash
sudo ./fedorable.sh --recommended -y
sudo ./fedorable.sh --all -y
sudo ./fedorable.sh --minimal --dry-run
sudo ./fedorable.sh --no-flatpak -y
```

**Modes:** `--minimal` `--recommended` `--all` `--none`

**Options:** `-y` (yes to all), `--dry-run` (preview only, no changes), `-q` (quiet), `--check-only`, `--config FILE`

**Skip tasks:** `--no-update` `--no-autoremove` `--no-clean-dnf` `--no-kernels` `--no-journal` `--no-temp` `--no-grub` `--no-flatpak` `--no-rpmdb` `--no-failed` `--no-trim` `--no-firmware` `--no-cache` `--no-coredumps`

## Tasks

| Task | Minimal | Recommended | Advanced |
|------|:-------:|:-----------:|:--------:|
| System update | ✓ | ✓ | pick |
| Reset failed units | ✓ | ✓ | pick |
| Autoremove | | ✓ | pick |
| DNF cache | | ✓ | pick |
| Old kernels | | ✓ | pick |
| Journal | | ✓ | pick |
| Temp files | | ✓ | pick |
| GRUB update | | ✓ | pick |
| Flatpak | | ✓ | pick |
| RPM db optimize | | | pick |
| TRIM | | ✓ | pick |
| Firmware | | | pick |
| User cache | | | pick |
| Coredumps | | ✓ | pick |

## Config

`/etc/fedorable.conf`:

```
KERNELS_TO_KEEP=3
JOURNAL_VACUUM_TIME="14d"
JOURNAL_VACUUM_SIZE="1G"
TEMP_FILE_AGE_DAYS=30
MIN_DISK_SPACE_MB=2048
```

Or use `--config /path/to/file.conf`.

## GUI (Under Development)

```bash
sudo dnf install python3-gobject gtk4 libadwaita

```



---

All tasks use standard Fedora tools (`dnf`, `journalctl`, `flatpak`, `fstrim`, etc.). No custom binaries. Use `--dry-run` to preview without making changes.

## License

[MIT](LICENSE)
