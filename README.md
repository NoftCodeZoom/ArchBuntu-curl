# ArchBuntu

Ubuntu meets Arch. Power meets simplicity.

An automated installer that turns a fresh Arch Linux ISO into a fully configured ArchBuntu system with GNOME, NVIDIA drivers, Yaru themes, and more.

## Installation

Boot into the official Arch Linux ISO, connect to the internet, then run:

```bash
curl -fsSL https://raw.githubusercontent.com/NoftCodeZoom/ArchBuntu-curl/main/install-archbuntu.sh | bash
```

## What it installs

- GNOME desktop with GDM
- NVIDIA proprietary drivers (open kernel module)
- Yaru icon, GTK, and shell themes
- Dash to Dock GNOME extension
- Yaru Color Picker (accent color switcher)
- systemd-boot bootloader
- paru AUR helper
