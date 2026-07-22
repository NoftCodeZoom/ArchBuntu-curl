#!/usr/bin/env bash

# ╔══════════════════════════════════════════════════════════╗
# ║                   ArchBuntu Installer                    ║
# ║          Ubuntu meets Arch. Power meets simplicity.      ║
# ╚══════════════════════════════════════════════════════════╝

set -euo pipefail

BOLD='\033[1m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

banner() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo "    _                         _   _                    _              "
    echo "   / \   _ __   __ _ _   _ __| | | |__  _   _ _ __ __| | ___ _ __   "
    echo "  / _ \ | '_ \ / _\` | | | |/ _\` | | '_ \| | | | '__/ _\` |/ _ \ '__|  "
    echo " / ___ \| | | | (_| | |_| | (_| | | |_) | |_| | | | (_| |  __/ |     "
    echo "/_/   \_\_| |_|\__,_|\__,_|\__,_| |_.__/ \__,_|_|  \__,_|\___|_|     "
    echo ""
    echo "         Ubuntu meets Arch. Power meets simplicity."
    echo -e "${NC}"
}

log() {
    echo -e "${GREEN}[ARCHBUNTU]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# ─── Pre-flight checks ───────────────────────────────────

preflight() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root."
    fi

    if [[ ! -d /sys/firmware/efi ]]; then
        error "UEFI system required. Legacy BIOS is not supported."
    fi

    if ! ping -c 1 archlinux.org &>/dev/null; then
        error "No internet connection. Please connect to the network first."
    fi

    log "Pre-flight checks passed."
}

# ─── User prompts ─────────────────────────────────────────

prompt_config() {
    echo ""
    echo -e "${BOLD}${CYAN}════════════════════════════════════════${NC}"
    echo -e "${BOLD}${CYAN}         ArchBuntu Configuration         ${NC}"
    echo -e "${BOLD}${CYAN}════════════════════════════════════════${NC}"
    echo ""

    # Disk selection
    echo -e "${BOLD}Available disks:${NC}"
    lsblk -dno NAME,SIZE,MODEL | grep -v "loop\|sr\|ram"
    echo ""
    read -rp "Target disk (e.g. /dev/sda or /dev/vda): " TARGET_DISK
    if [[ ! -b "$TARGET_DISK" ]]; then
        error "Disk $TARGET_DISK does not exist."
    fi

    # Hostname
    read -rp "Hostname [archbuntu]: " HOSTNAME
    HOSTNAME=${HOSTNAME:-archbuntu}

    # Username
    read -rp "Username: " USERNAME
    if [[ -z "$USERNAME" ]]; then
        error "Username cannot be empty."
    fi

    # Password
    read -rs -p "Password for $USERNAME: " USER_PASS
    echo ""
    read -rs -p "Confirm password: " USER_PASS_CONFIRM
    echo ""
    if [[ "$USER_PASS" != "$USER_PASS_CONFIRM" ]]; then
        error "Passwords do not match."
    fi

    # Root password
    read -rs -p "Root password: " ROOT_PASS
    echo ""
    read -rs -p "Confirm root password: " ROOT_PASS_CONFIRM
    echo ""
    if [[ "$ROOT_PASS" != "$ROOT_PASS_CONFIRM" ]]; then
        error "Root passwords do not match."
    fi

    # Timezone
    read -rp "Timezone [Asia/Kolkata]: " TIMEZONE
    TIMEZONE=${TIMEZONE:-Asia/Kolkata}

    # Mirror country
    read -rp "Mirror country for reflector (e.g. US, IN, DE) [IN]: " MIRROR_COUNTRY
    MIRROR_COUNTRY=${MIRROR_COUNTRY:-IN}

    echo ""
    echo -e "${BOLD}Summary:${NC}"
    echo "  Disk:       $TARGET_DISK (will be erased!)"
    echo "  Hostname:   $HOSTNAME"
    echo "  Username:   $USERNAME"
    echo "  Timezone:   $TIMEZONE"
    echo "  Mirrors:    $MIRROR_COUNTRY"
    echo ""
    read -rp "Proceed? This will ERASE $TARGET_DISK. [y/N]: " CONFIRM
    if [[ "${CONFIRM,,}" != "y" ]]; then
        error "Installation cancelled."
    fi
}

# ─── Partitioning (UEFI + systemd-boot) ───────────────────

partition_disk() {
    log "Partitioning $TARGET_DISK..."

    # Wipe and create GPT
    wipefs -af "$TARGET_DISK" &>/dev/null
    sgdisk --zap-all "$TARGET_DISK" &>/dev/null

    # EFI partition (512MB)
    sgdisk -n 1:0:+512M -t 1:ef00 -c 1:"EFI" "$TARGET_DISK"

    # Root partition (rest of disk)
    sgdisk -n 2:0:0 -t 2:8300 -c 2:"ROOT" "$TARGET_DISK"

    # Wait for kernel to pick up partitions
    partprobe "$TARGET_DISK"
    sleep 2

    # Determine partition names
    if [[ "$TARGET_DISK" == *"nvme"* ]] || [[ "$TARGET_DISK" == *"mmcblk"* ]]; then
        EFI_PART="${TARGET_DISK}p1"
        ROOT_PART="${TARGET_DISK}p2"
    else
        EFI_PART="${TARGET_DISK}1"
        ROOT_PART="${TARGET_DISK}2"
    fi

    # Format
    log "Formatting partitions..."
    mkfs.fat -F32 "$EFI_PART" &>/dev/null
    mkfs.ext4 -F "$ROOT_PART" &>/dev/null

    # Mount
    log "Mounting partitions..."
    mount "$ROOT_PART" /mnt
    mkdir -p /mnt/boot
    mount "$EFI_PART" /mnt/boot
}

# ─── Mirrors ──────────────────────────────────────────────

setup_mirrors() {
    log "Setting up mirrors for $MIRROR_COUNTRY..."
    pacman -S --noconfirm reflector &>/dev/null
    reflector --country "$MIRROR_COUNTRY" --age 12 --protocol https --sort rate --save /etc/pacman.d/mirrorlist &>/dev/null || warn "Reflector failed, using default mirrors."
}

# ─── Base install ─────────────────────────────────────────

install_base() {
    log "Installing base system..."
    pacstrap /mnt base linux linux-headers linux-firmware nano networkmanager sudo git base-devel &>/dev/null

    log "Generating fstab..."
    genfstab -U /mnt >> /mnt/etc/fstab
}

# ─── Configure system (inside chroot) ─────────────────────

configure_system() {
    log "Configuring system..."

    # Create the post-chroot script
    cat > /mnt/root/configure.sh << 'CHROOT_SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

# ─── Variables (passed from host) ───
HOSTNAME="__HOSTNAME__"
USERNAME="__USERNAME__"
USER_PASS="__USER_PASS__"
ROOT_PASS="__ROOT_PASS__"
TIMEZONE="__TIMEZONE__"

# ─── Locale ───
echo "Setting locale..."
sed -i 's/^#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
locale-gen &>/dev/null
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# ─── Timezone ───
echo "Setting timezone..."
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc

# ─── Hostname ───
echo "$HOSTNAME" > /etc/hostname

# ─── Users ───
echo "Creating users..."
echo "root:$ROOT_PASS" | chpasswd
useradd -m -G wheel -s /bin/bash "$USERNAME"
echo "$USERNAME:$USER_PASS" | chpasswd

# ─── Sudo ───
echo "%wheel ALL=(ALL:ALL) NOPASSWD: ALL" > /etc/sudoers.d/wheel

# ─── Enable services ───
echo "Enabling services..."
systemctl enable NetworkManager &>/dev/null
systemctl enable gdm &>/dev/null

# ─── Enable multilib ───
echo "Enabling multilib repo..."
sed -i '/#\[multilib\]/{N;s/#\[multilib\]\n#Include/\[multilib\]\nInclude/}' /etc/pacman.conf

# ─── Enable parallel downloads ───
sed -i 's/^#ParallelDownloads/ParallelDownloads/' /etc/pacman.conf

# ─── Sync ───
pacman -Sy --noconfirm &>/dev/null

# ─── Install GNOME + NVIDIA + packages ───
echo "Installing GNOME desktop + NVIDIA drivers..."
pacman -S --noconfirm \
    gnome gnome-tweaks gnome-terminal \
    nvidia-open-dkms nvidia-utils lib32-nvidia-utils nvidia-settings nvidia-prime egl-wayland egl-wayland2 \
    noto-fonts noto-fonts-cjk noto-fonts-emoji ttf-liberation ttf-dejavu \
    base-devel \
    &>/dev/null

# ─── Configure NVIDIA ───
echo "Configuring NVIDIA..."
echo "options nvidia-drm modeset=1" > /etc/modprobe.d/nvidia-drm.conf
sed -i 's/^MODULES=()/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf

# ─── Kernel command line ───
ROOT_UUID=$(blkid -s UUID -o value __ROOT_PART__)
echo "root=UUID=$ROOT_UUID rw rootfstype=ext4 nvidia-drm.modeset=1" > /etc/kernel/cmdline

# ─── Bootloader (systemd-boot) ───
echo "Installing systemd-boot..."
bootctl install &>/dev/null

cat > /boot/loader/entries/archbuntu.conf << EOF
title   ArchBuntu
linux   /vmlinuz-linux
initrd  /initramfs-linux.img
options root=UUID=$ROOT_UUID rw rootfstype=ext4 nvidia-drm.modeset=1
EOF

cat > /boot/loader/loader.conf << 'EOF'
default  archbuntu.conf
timeout  5
console-mode max
editor   no
EOF

# ─── Rebuild initramfs ───
echo "Building initramfs..."
mkinitcpio -P &>/dev/null

# ─── Install paru (AUR helper) ───
echo "Installing paru AUR helper..."
cd /tmp
sudo -u "$USERNAME" bash -c '
    git clone https://aur.archlinux.org/paru-bin.git /tmp/paru-bin 2>/dev/null
    cd /tmp/paru-bin
    makepkg -si --noconfirm 2>/dev/null
'
rm -rf /tmp/paru-bin

# ─── Install Yaru themes + Dash to Dock ───
echo "Installing Yaru themes and Dash to Dock..."
sudo -u "$USERNAME" bash -c '
    paru -S --noconfirm \
        yaru-icon-theme yaru-gtk-theme yaru-gnome-shell-theme \
        gnome-shell-extension-dash-to-dock \
        2>/dev/null
'

# ─── Install Ubuntu wallpapers ───
echo "Installing Ubuntu wallpapers..."
sudo -u "$USERNAME" bash -c '
    paru -S --noconfirm ubuntu-wallpapers-noble 2>/dev/null || true
'

# ─── Enable GNOME extensions ───
echo "Enabling Dash to Dock..."
sudo -u "$USERNAME" bash -c '
    gsettings set org.gnome.shell enabled-extensions "[\"dash-to-dock@micxgx.gmail.com\"]" 2>/dev/null || true
'

# ─── Apply Yaru theme ───
echo "Applying ArchBuntu theme..."
sudo -u "$USERNAME" bash -c '
    gsettings set org.gnome.desktop.interface icon-theme "Yaru" 2>/dev/null || true
    gsettings set org.gnome.desktop.interface gtk-theme "Yaru" 2>/dev/null || true
    gsettings set org.gnome.desktop.interface accent-color "orange" 2>/dev/null || true
    gsettings set org.gnome.desktop.interface color-scheme "prefer-dark" 2>/dev/null || true
'

# ─── Install Yaru Color Picker script ───
echo "Setting up Yaru Color Picker..."
sudo -u "$USERNAME" mkdir -p /home/$USERNAME/.local/share/applications

sudo -u "$USERNAME" bash -c 'cat > ~/Desktop/yaru-color-picker.sh << "SCRIPT"
#!/bin/bash
while true; do
    echo "=== Yaru Color Picker ==="
    echo ""
    echo "  1) Blue"
    echo "  2) Red"
    echo "  3) Purple"
    echo "  4) Sage"
    echo "  5) Magenta"
    echo "  6) Olive"
    echo "  7) Prussian Green"
    echo "  8) Yellow"
    echo "  9) Warty Brown"
    echo "  0) Reset to Yaru (default)"
    echo ""
    read -p "Pick a color [1-9/0]: " choice
    case $choice in
        1) color="Yaru-blue"; accent="blue" ;;
        2) color="Yaru-red"; accent="red" ;;
        3) color="Yaru-purple"; accent="purple" ;;
        4) color="Yaru-sage"; accent="green" ;;
        5) color="Yaru-magenta"; accent="pink" ;;
        6) color="Yaru-olive"; accent="yellow" ;;
        7) color="Yaru-prussiangreen"; accent="teal" ;;
        8) color="Yaru-yellow"; accent="yellow" ;;
        9) color="Yaru-wartybrown"; accent="orange" ;;
        0) color="Yaru"; accent="blue" ;;
        *) echo "Invalid choice. Try again."; echo ""; continue ;;
    esac
    gsettings set org.gnome.desktop.interface icon-theme "$color"
    gsettings set org.gnome.desktop.interface accent-color "$accent"
    echo "Icon theme: $color | Accent: $accent"
    break
done
SCRIPT
chmod +x ~/Desktop/yaru-color-picker.sh'

# ─── Autostart entry for color picker ───
sudo -u "$USERNAME" bash -c 'cat > ~/.local/share/applications/yaru-color-picker.desktop << "DESKTOP"
[Desktop Entry]
Name=Yaru Color Picker
Comment=Change Yaru icon accent color
Exec=kgx -e /home/__USERNAME__/Desktop/yaru-color-picker.sh
Icon=org.gnome.Console
Terminal=false
Type=Application
Categories=Settings;
DESKTOP'

# ─── Done ───
echo ""
echo "ArchBuntu installation complete!"
echo "Remove installation media and reboot."

CHROOT_SCRIPT

    # Replace placeholders with actual values
    sed -i "s|__HOSTNAME__|$HOSTNAME|g" /mnt/root/configure.sh
    sed -i "s|__USERNAME__|$USERNAME|g" /mnt/root/configure.sh
    sed -i "s|__USER_PASS__|$USER_PASS|g" /mnt/root/configure.sh
    sed -i "s|__ROOT_PASS__|$ROOT_PASS|g" /mnt/root/configure.sh
    sed -i "s|__TIMEZONE__|$TIMEZONE|g" /mnt/root/configure.sh
    sed -i "s|__ROOT_PART__|$ROOT_PART|g" /mnt/root/configure.sh

    chmod +x /mnt/root/configure.sh

    # Run inside chroot
    arch-chroot /mnt /root/configure.sh

    # Cleanup
    rm /mnt/root/configure.sh
}

# ─── Main ─────────────────────────────────────────────────

main() {
    banner
    preflight
    prompt_config
    setup_mirrors
    partition_disk
    install_base
    configure_system

    echo ""
    log "══════════════════════════════════════════"
    log "  ArchBuntu installed successfully!"
    log "  Reboot to enjoy your new system."
    log "══════════════════════════════════════════"
}

main "$@"
