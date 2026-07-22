#!/usr/bin/env bash

# ╔══════════════════════════════════════════════════════════╗
# ║                   ArchBuntu Installer                    ║
# ║          Ubuntu meets Arch. Power meets simplicity.      ║
# ╚══════════════════════════════════════════════════════════╝

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
    cat << 'EOF'
     ___      .______        ______  __    __  .______    __    __  .__   __. .___________. __    __  
    /   \     |   _  \      /      ||  |  |  | |   _  \  |  |  |  | |  \ |  | |           ||  |  |  | 
   /  ^  \    |  |_)  |    |  ,----'|  |__|  | |  |_)  | |  |  |  | |   \|  | `---|  |----`|  |  |  | 
  /  /_\  \   |      /     |  |     |   __   | |   _  <  |  |  |  | |  . `  |     |  |     |  |  |  | 
 /  _____  \  |  |\  \----.|  `----.|  |  |  | |  |_)  | |  `--'  | |  |\   |     |  |     |  `--'  | 
/__/     \__\ | _| `._____| \______||__|  |__| |______/   \______/  |__| \__|     |__|      \______/  
EOF
    echo ""
    echo -e "          ${BOLD}Ubuntu meets Arch. Power meets simplicity.${NC}"
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

# ─── Partition mode ───────────────────────────────────────

choose_partition_mode() {
    echo ""
    echo -e "${BOLD}${CYAN}════════════════════════════════════════${NC}"
    echo -e "${BOLD}${CYAN}          Partition Mode               ${NC}"
    echo -e "${BOLD}${CYAN}════════════════════════════════════════${NC}"
    echo ""
    echo "  1) Auto-partition (entire disk, erases everything)"
    echo "  2) Manual partition (you partition before running)"
    echo ""
    read -rp "Choose [1/2]: " PART_MODE
    PART_MODE=${PART_MODE:-1}
}

# ─── User prompts ─────────────────────────────────────────

prompt_config() {
    echo ""
    echo -e "${BOLD}${CYAN}════════════════════════════════════════${NC}"
    echo -e "${BOLD}${CYAN}         ArchBuntu Configuration         ${NC}"
    echo -e "${BOLD}${CYAN}════════════════════════════════════════${NC}"
    echo ""

    echo -e "${BOLD}Available disks:${NC}"
    lsblk -dno NAME,SIZE,MODEL | grep -v "loop\|sr\|ram"
    echo ""
    read -rp "Target disk (e.g. /dev/sda or /dev/vda): " TARGET_DISK
    if [[ ! -b "$TARGET_DISK" ]]; then
        error "Disk $TARGET_DISK does not exist."
    fi

    if [[ "$PART_MODE" == "1" ]]; then
        EFI_PART=""
        ROOT_PART=""
    else
        echo ""
        echo -e "${BOLD}Enter your pre-created partitions:${NC}"
        read -rp "EFI partition (e.g. /dev/sda1): " EFI_PART
        read -rp "Root partition (e.g. /dev/sda2): " ROOT_PART
        if [[ ! -b "$EFI_PART" ]] || [[ ! -b "$ROOT_PART" ]]; then
            error "Partition(s) do not exist."
        fi
    fi

    read -rp "Hostname [archbuntu]: " HOSTNAME
    HOSTNAME=${HOSTNAME:-archbuntu}

    read -rp "Username: " USERNAME
    if [[ -z "$USERNAME" ]]; then
        error "Username cannot be empty."
    fi

    read -rs -p "Password for $USERNAME: " USER_PASS
    echo ""
    read -rs -p "Confirm password: " USER_PASS_CONFIRM
    echo ""
    if [[ "$USER_PASS" != "$USER_PASS_CONFIRM" ]]; then
        error "Passwords do not match."
    fi

    read -rs -p "Root password: " ROOT_PASS
    echo ""
    read -rs -p "Confirm root password: " ROOT_PASS_CONFIRM
    echo ""
    if [[ "$ROOT_PASS" != "$ROOT_PASS_CONFIRM" ]]; then
        error "Root passwords do not match."
    fi

    read -rp "Timezone [Asia/Kolkata]: " TIMEZONE
    TIMEZONE=${TIMEZONE:-Asia/Kolkata}

    read -rp "Mirror country for reflector (e.g. US, IN, DE) [IN]: " MIRROR_COUNTRY
    MIRROR_COUNTRY=${MIRROR_COUNTRY:-IN}

    echo ""
    log "Summary:"
    echo "  Disk:       $TARGET_DISK (will be erased!)"
    echo "  Part mode:  $([ "$PART_MODE" == "1" ] && echo "Auto" || echo "Manual")"
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

# ─── Driver selection ─────────────────────────────────────

choose_drivers() {
    echo ""
    echo -e "${BOLD}${CYAN}════════════════════════════════════════${NC}"
    echo -e "${BOLD}${CYAN}          Driver Selection               ${NC}"
    echo -e "${BOLD}${CYAN}════════════════════════════════════════${NC}"
    echo ""
    echo "  1) NVIDIA (open kernel module - recommended for RTX 20+)"
    echo "  2) NVIDIA (proprietary - legacy closed-source)"
    echo "  3) AMD (AMDGPU - open source)"
    echo "  4) Intel (integrated graphics)"
    echo "  5) VirtualBox Guest Additions"
    echo "  6) None (skip GPU drivers)"
    echo ""
    read -rp "Choose driver [1-6]: " DRIVER_CHOICE
    DRIVER_CHOICE=${DRIVER_CHOICE:-1}
}

# ─── Optional repositories ────────────────────────────────

choose_repos() {
    echo ""
    echo -e "${BOLD}${CYAN}════════════════════════════════════════${NC}"
    echo -e "${BOLD}${CYAN}         Optional Repositories           ${NC}"
    echo -e "${BOLD}${CYAN}════════════════════════════════════════${NC}"
    echo ""
    echo "  [x] multilib (32-bit libs - Wine, Steam, etc.)"
    echo ""
    read -rp "Enable multilib? [Y/n]: " ENABLE_MULTILIB
    ENABLE_MULTILIB=${ENABLE_MULTILIB:-y}
}

# ─── Optional packages ────────────────────────────────────

choose_packages() {
    echo ""
    echo -e "${BOLD}${CYAN}════════════════════════════════════════${NC}"
    echo -e "${BOLD}${CYAN}          Optional Packages              ${NC}"
    echo -e "${BOLD}${CYAN}════════════════════════════════════════${NC}"
    echo ""
    echo "  [x] Firefox (web browser)"
    echo "  [x] VLC (media player)"
    echo "  [x] Htop (system monitor)"
    echo "  [x] Fastfetch"
    echo "  [x] Flatpak support"
    echo "  [x] USB utils (usbutils)"
    echo "  [x] Bluetooth support (bluez bluez-utils)"
    echo ""
    read -rp "Enable all optional packages? [Y/n]: " ENABLE_OPTIONAL
    ENABLE_OPTIONAL=${ENABLE_OPTIONAL:-y}

    echo ""
    echo "  Extra packages (space-separated, or leave empty):"
    echo "  Examples: discord steam obs-studio gimp code"
    read -rp "Extra packages: " EXTRA_PACKAGES
}

# ─── Partitioning ─────────────────────────────────────────

partition_disk() {
    if [[ "$PART_MODE" == "1" ]]; then
        log "Auto-partitioning $TARGET_DISK..."

        wipefs -af "$TARGET_DISK" &>/dev/null
        sgdisk --zap-all "$TARGET_DISK" &>/dev/null

        sgdisk -n 1:0:+512M -t 1:ef00 -c 1:"EFI" "$TARGET_DISK"
        sgdisk -n 2:0:0 -t 2:8300 -c 2:"ROOT" "$TARGET_DISK"

        partprobe "$TARGET_DISK"
        sleep 2

        if [[ "$TARGET_DISK" == *"nvme"* ]] || [[ "$TARGET_DISK" == *"mmcblk"* ]]; then
            EFI_PART="${TARGET_DISK}p1"
            ROOT_PART="${TARGET_DISK}p2"
        else
            EFI_PART="${TARGET_DISK}1"
            ROOT_PART="${TARGET_DISK}2"
        fi

        log "Formatting partitions..."
        mkfs.fat -F32 "$EFI_PART"
        mkfs.ext4 -F "$ROOT_PART"
    else
        log "Using manual partitions..."
        mkfs.fat -F32 "$EFI_PART"
        mkfs.ext4 -F "$ROOT_PART"
    fi

    log "Mounting partitions..."
    mount "$ROOT_PART" /mnt
    mkdir -p /mnt/boot
    mount "$EFI_PART" /mnt/boot
}

# ─── Mirrors ──────────────────────────────────────────────

setup_mirrors() {
    log "Setting up mirrors for $MIRROR_COUNTRY..."
    pacman -S --noconfirm reflector || true
    reflector --country "$MIRROR_COUNTRY" --age 12 --protocol https --sort rate --save /etc/pacman.d/mirrorlist || warn "Reflector failed, using default mirrors."
}

# ─── Base install ─────────────────────────────────────────

install_base() {
    log "Installing base system..."
    pacstrap /mnt base linux linux-headers linux-firmware nano networkmanager sudo git base-devel

    log "Generating fstab..."
    genfstab -U /mnt >> /mnt/etc/fstab
}

# ─── Configure system (inside chroot) ─────────────────────

configure_system() {
    log "Configuring system..."

    # Write the chroot script as a real file (NOT a heredoc with set -e)
    cat > /mnt/root/configure.sh << 'CHROOT_SCRIPT'
#!/usr/bin/env bash

HOSTNAME="__HOSTNAME__"
USERNAME="__USERNAME__"
USER_PASS="__USER_PASS__"
ROOT_PASS="__ROOT_PASS__"
TIMEZONE="__TIMEZONE__"
DRIVER_CHOICE="__DRIVER_CHOICE__"
ENABLE_MULTILIB="__ENABLE_MULTILIB__"
ENABLE_OPTIONAL="__ENABLE_OPTIONAL__"
EXTRA_PACKAGES="__EXTRA_PACKAGES__"
ROOT_PART="__ROOT_PART__"

# NO set -e — we handle errors manually so the script never dies silently

echo "[ARCHBUNTU] === Starting ArchBuntu configuration ==="

# ─── Locale ───
echo "[ARCHBUNTU] Setting locale..."
sed -i 's/^#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# ─── Timezone ───
echo "[ARCHBUNTU] Setting timezone..."
ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
hwclock --systohc

# ─── Hostname ───
echo "$HOSTNAME" > /etc/hostname

# ─── Users ───
echo "[ARCHBUNTU] Creating users..."
echo "root:$ROOT_PASS" | chpasswd
useradd -m -G wheel -s /bin/bash "$USERNAME"
echo "$USERNAME:$USER_PASS" | chpasswd

# ─── Sudo ───
echo "%wheel ALL=(ALL:ALL) NOPASSWD: ALL" > /etc/sudoers.d/wheel

# ─── Enable multilib ───
if [[ "$ENABLE_MULTILIB" == "y" ]]; then
    echo "[ARCHBUNTU] Enabling multilib repo..."
    if ! grep -q '^\[multilib\]' /etc/pacman.conf; then
        sed -i '/#\[multilib\]/,/#Include/{
            s/#\[multilib\]/[multilib]/
            s/#Include/Include/
        }' /etc/pacman.conf
    fi
fi

# ─── Enable parallel downloads ───
sed -i 's/^#ParallelDownloads/ParallelDownloads/' /etc/pacman.conf || true

# ─── Sync ───
echo "[ARCHBUNTU] Syncing package databases..."
pacman -Sy --noconfirm

# ─── Build package list ───
echo "[ARCHBUNTU] Building package list..."
INSTALL_PKGS="base-devel sudo git nano networkmanager gdm gnome gnome-tweaks noto-fonts noto-fonts-cjk noto-fonts-emoji ttf-liberation ttf-dejavu kgx"

# ─── Driver packages ───
case "$DRIVER_CHOICE" in
    1)
        echo "[ARCHBUNTU] Adding NVIDIA (open) drivers..."
        INSTALL_PKGS="$INSTALL_PKGS nvidia-open-dkms nvidia-utils lib32-nvidia-utils nvidia-settings nvidia-prime egl-wayland"
        ;;
    2)
        echo "[ARCHBUNTU] Adding NVIDIA (proprietary) drivers..."
        INSTALL_PKGS="$INSTALL_PKGS nvidia-dkms nvidia-utils lib32-nvidia-utils nvidia-settings nvidia-prime egl-wayland"
        ;;
    3)
        echo "[ARCHBUNTU] Adding AMD drivers..."
        INSTALL_PKGS="$INSTALL_PKGS mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon xf86-video-amdgpu"
        ;;
    4)
        echo "[ARCHBUNTU] Adding Intel drivers..."
        INSTALL_PKGS="$INSTALL_PKGS mesa lib32-mesa vulkan-intel lib32-vulkan-intel xf86-video-intel"
        ;;
    5)
        echo "[ARCHBUNTU] Adding VirtualBox Guest Additions..."
        INSTALL_PKGS="$INSTALL_PKGS virtualbox-guest-utils virtualbox-guest-modules-arch"
        ;;
    6)
        echo "[ARCHBUNTU] No GPU drivers selected."
        ;;
esac

# ─── Optional packages ───
if [[ "$ENABLE_OPTIONAL" == "y" ]]; then
    echo "[ARCHBUNTU] Adding optional packages..."
    INSTALL_PKGS="$INSTALL_PKGS firefox vlc htop fastfetch flatpak usbutils bluez bluez-utils"
fi

# ─── Extra packages ───
if [[ -n "$EXTRA_PACKAGES" ]]; then
    echo "[ARCHBUNTU] Adding extra packages: $EXTRA_PACKAGES"
    INSTALL_PKGS="$INSTALL_PKGS $EXTRA_PACKAGES"
fi

# ─── Install all packages ───
echo "[ARCHBUNTU] Installing packages: $INSTALL_PKGS"
pacman -S --noconfirm --needed $INSTALL_PKGS
echo "[ARCHBUNTU] Package installation complete."

# ─── Enable services ───
echo "[ARCHBUNTU] Enabling services..."
systemctl enable gdm
systemctl enable NetworkManager
systemctl enable bluetooth 2>/dev/null || true
systemctl enable vboxservice 2>/dev/null || true

# ─── Configure NVIDIA (if applicable) ───
ROOT_UUID=$(blkid -s UUID -o value "$ROOT_PART")

if [[ "$DRIVER_CHOICE" == "1" ]] || [[ "$DRIVER_CHOICE" == "2" ]]; then
    echo "[ARCHBUNTU] Configuring NVIDIA..."
    echo "options nvidia-drm modeset=1" > /etc/modprobe.d/nvidia-drm.conf
    sed -i 's/^MODULES=()/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf
    echo "root=UUID=$ROOT_UUID rw rootfstype=ext4 nvidia-drm.modeset=1" > /etc/kernel/cmdline
else
    echo "root=UUID=$ROOT_UUID rw rootfstype=ext4" > /etc/kernel/cmdline
fi

# ─── Bootloader (systemd-boot) ───
echo "[ARCHBUNTU] Installing systemd-boot..."
bootctl install

cat > /boot/loader/entries/archbuntu.conf << EOF
title   ArchBuntu
linux   /vmlinuz-linux
initrd  /initramfs-linux.img
options root=UUID=$ROOT_UUID rw rootfstype=ext4 $(if [[ "$DRIVER_CHOICE" == "1" ]] || [[ "$DRIVER_CHOICE" == "2" ]]; then echo "nvidia-drm.modeset=1"; fi)
EOF

cat > /boot/loader/loader.conf << 'EOF'
default  archbuntu.conf
timeout  5
console-mode max
editor   no
EOF

# ─── Rebuild initramfs ───
echo "[ARCHBUNTU] Building initramfs..."
mkinitcpio -P

# ─── Install paru (AUR helper) ───
echo "[ARCHBUNTU] Installing paru AUR helper..."
cd /tmp
sudo -u "$USERNAME" bash -c '
    git clone https://aur.archlinux.org/paru-bin.git /tmp/paru-bin
    cd /tmp/paru-bin
    makepkg -si --noconfirm
' || echo "[ARCHBUNTU] WARNING: paru installation failed. AUR packages will need manual installation."
rm -rf /tmp/paru-bin

# ─── Install Yaru themes + Dash to Dock via paru ───
echo "[ARCHBUNTU] Installing Yaru themes and Dash to Dock..."
sudo -u "$USERNAME" bash -c '
    paru -S --noconfirm --needed \
        yaru-icon-theme yaru-gtk-theme yaru-gnome-shell-theme \
        gnome-shell-extension-dash-to-dock
' || echo "[ARCHBUNTU] WARNING: AUR theme installation failed. Will retry on first login."

# ─── Create first-login setup script ───
echo "[ARCHBUNTU] Creating first-login setup..."
sudo -u "$USERNAME" mkdir -p "/home/$USERNAME/.config/autostart"
sudo -u "$USERNAME" mkdir -p "/home/$USERNAME/.local/share/applications"
sudo -u "$USERNAME" mkdir -p "/home/$USERNAME/Desktop"

# Write the first-login script
cat > "/home/$USERNAME/.config/archbuntu-first-setup.sh" << 'FIRSTSETUP'
#!/bin/bash
echo "[ARCHBUNTU] Applying ArchBuntu theme..."

# Enable Dash to Dock
gsettings set org.gnome.shell enabled-extensions "['dash-to-dock@micxgx.gmail.com']" 2>/dev/null || true

# Apply Yaru theme + dark mode
gsettings set org.gnome.desktop.interface icon-theme "Yaru" 2>/dev/null || true
gsettings set org.gnome.desktop.interface gtk-theme "Yaru" 2>/dev/null || true
gsettings set org.gnome.desktop.interface accent-color "orange" 2>/dev/null || true
gsettings set org.gnome.desktop.interface color-scheme "prefer-dark" 2>/dev/null || true

# Apply wallpaper
if [[ -f /usr/share/backgrounds/ArchBuntu/wallpaper-dark.png ]]; then
    gsettings set org.gnome.desktop.background picture-uri "file:///usr/share/backgrounds/ArchBuntu/wallpaper-dark.png"
    gsettings set org.gnome.desktop.background picture-uri-dark "file:///usr/share/backgrounds/ArchBuntu/wallpaper-dark.png"
fi

# Cleanup: run once then delete
rm -f ~/.config/autostart/archbuntu-first-setup.desktop
rm -f ~/.config/archbuntu-first-setup.sh

echo "[ARCHBUNTU] First-time setup complete!"
FIRSTSETUP
chmod +x "/home/$USERNAME/.config/archbuntu-first-setup.sh"
chown "$USERNAME:$USERNAME" "/home/$USERNAME/.config/archbuntu-first-setup.sh"

# Autostart .desktop
cat > "/home/$USERNAME/.config/autostart/archbuntu-first-setup.desktop" << AUTOSTART
[Desktop Entry]
Type=Application
Name=ArchBuntu First Setup
Exec=/bin/bash -c '\$HOME/.config/archbuntu-first-setup.sh'
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
AUTOSTART
chown "$USERNAME:$USERNAME" "/home/$USERNAME/.config/autostart/archbuntu-first-setup.desktop"

# ─── Yaru Color Picker script ───
echo "[ARCHBUNTU] Setting up Yaru Color Picker..."
cat > "/home/$USERNAME/Desktop/yaru-color-picker.sh" << 'SCRIPT'
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
chmod +x "/home/$USERNAME/Desktop/yaru-color-picker.sh"
chown "$USERNAME:$USERNAME" "/home/$USERNAME/Desktop/yaru-color-picker.sh"

# Color picker .desktop file
cat > "/home/$USERNAME/.local/share/applications/yaru-color-picker.desktop" << DESKTOP
[Desktop Entry]
Name=Yaru Color Picker
Comment=Change Yaru icon accent color
Exec=kgx -e /home/$USERNAME/Desktop/yaru-color-picker.sh
Icon=org.gnome.Console
Terminal=false
Type=Application
Categories=Settings;
DESKTOP
chown "$USERNAME:$USERNAME" "/home/$USERNAME/.local/share/applications/yaru-color-picker.desktop"

echo ""
echo "[ARCHBUNTU] ========================================"
echo "[ARCHBUNTU]   ArchBuntu installation complete!"
echo "[ARCHBUNTU]   Remove installation media and reboot."
echo "[ARCHBUNTU] ========================================"

CHROOT_SCRIPT

    # Replace placeholders
    sed -i "s|__HOSTNAME__|$HOSTNAME|g" /mnt/root/configure.sh
    sed -i "s|__USERNAME__|$USERNAME|g" /mnt/root/configure.sh
    sed -i "s|__USER_PASS__|$USER_PASS|g" /mnt/root/configure.sh
    sed -i "s|__ROOT_PASS__|$ROOT_PASS|g" /mnt/root/configure.sh
    sed -i "s|__TIMEZONE__|$TIMEZONE|g" /mnt/root/configure.sh
    sed -i "s|__DRIVER_CHOICE__|$DRIVER_CHOICE|g" /mnt/root/configure.sh
    sed -i "s|__ENABLE_MULTILIB__|$ENABLE_MULTILIB|g" /mnt/root/configure.sh
    sed -i "s|__ENABLE_OPTIONAL__|$ENABLE_OPTIONAL|g" /mnt/root/configure.sh
    sed -i "s|__EXTRA_PACKAGES__|$EXTRA_PACKAGES|g" /mnt/root/configure.sh
    sed -i "s|__ROOT_PART__|$ROOT_PART|g" /mnt/root/configure.sh

    chmod +x /mnt/root/configure.sh

    log "Running configuration in chroot..."
    arch-chroot /mnt /root/configure.sh
    EXIT_CODE=$?

    if [[ $EXIT_CODE -ne 0 ]]; then
        warn "Chroot script exited with errors (code $EXIT_CODE). Check output above."
    fi

    # Cleanup
    rm -f /mnt/root/configure.sh
}

# ─── Main ─────────────────────────────────────────────────

main() {
    banner
    preflight
    choose_partition_mode
    choose_drivers
    choose_repos
    choose_packages
    prompt_config
    setup_mirrors
    partition_disk
    install_base
    configure_system

    echo ""
    log "══════════════════════════════════════════"
    log "  ArchBuntu installed successfully!"
    log "  Remove install media and reboot."
    log "══════════════════════════════════════════"
}

main "$@"
