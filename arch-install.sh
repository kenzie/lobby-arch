#!/usr/bin/env bash
set -euo pipefail

echo "======================================="
echo "ARCH LOBBY INSTALLER (Interactive)"
echo "All data on the target disk will be erased!"
echo "======================================="

# --- List available disks ---
echo "Available disks:"
lsblk -d -o NAME,SIZE,MODEL
echo

# --- Prompt for target disk ---
echo -n "Enter target disk (e.g., nvme0n1, sda): "
read DISK
[[ ! "$DISK" =~ ^/dev/ ]] && DISK="/dev/$DISK"
[[ ! -b "$DISK" ]] && echo "Error: $DISK not valid" && exit 1

echo "You selected $DISK. All data will be erased!"
echo -n "Are you sure? (y/N): "
read CONFIRM
[[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]] && echo "Aborting." && exit 1

# --- Set fixed hostname/user ---
HOSTNAME="lobby-screen"
USERNAME="lobby"

echo -n "Password for new user: "
stty -echo
read PASSWORD
stty echo
echo

echo -n "Timezone (default America/Halifax): "
read TIMEZONE
TIMEZONE=${TIMEZONE:-America/Halifax}

echo -n "Locale (default en_US.UTF-8): "
read LOCALE
LOCALE=${LOCALE:-en_US.UTF-8}

# --- Clean disk ---
echo "==> Cleaning $DISK..."
swapoff -a
umount -R "$DISK"* || true
sgdisk --zap-all "$DISK"
sgdisk -g "$DISK"
partprobe "$DISK"
sleep 2

# --- Partitioning ---
EFI_SIZE="512MiB"
ROOT_PART="100%"

echo "==> Creating partitions..."
parted --script "$DISK" mklabel gpt \
    mkpart primary fat32 1MiB $EFI_SIZE set 1 esp on \
    mkpart primary ext4 $EFI_SIZE $ROOT_PART

# --- Determine partitions ---
if [[ "$DISK" =~ nvme ]]; then
    EFI="${DISK}p1"
    ROOT="${DISK}p2"
else
    EFI="${DISK}1"
    ROOT="${DISK}2"
fi
echo "EFI: $EFI, ROOT: $ROOT"

# --- Format & label partitions ---
echo "==> Formatting partitions..."
mkfs.fat -F32 "$EFI"
fatlabel "$EFI" EFI

mkfs.ext4 -F "$ROOT" -L ROOT

# --- Mount ---
mount "$ROOT" /mnt
mkdir -p /mnt/boot
mount -t vfat "$EFI" /mnt/boot

# --- Install base system + Hyprland + Plymouth (no spinner theme) ---
echo "==> Installing base packages..."
pacstrap /mnt base linux linux-firmware vim networkmanager sudo git \
    base-devel openssh rng-tools curl \
    hyprland swaybg xorg-server \
    xdg-desktop-portal xdg-desktop-portal-wlr \
    alacritty \
    chromium nginx python python-pip rclone \
    nodejs npm \
    plymouth cdrtools

genfstab -U /mnt >> /mnt/etc/fstab

# --- Chroot configuration ---
arch-chroot /mnt /bin/bash <<EOF
set -e

# Timezone & locale
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc
echo "$LOCALE UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=$LOCALE" > /etc/locale.conf

# Hostname
echo "$HOSTNAME" > /etc/hostname
echo "127.0.0.1 localhost" >> /etc/hosts

# Bootloader (systemd-boot)
bootctl --path=/boot install
ROOT_UUID=\$(blkid -s UUID -o value "$ROOT")
cat > /boot/loader/entries/arch.conf <<ENTRY
title   Arch Linux
linux   /vmlinuz-linux
initrd  /initramfs-linux.img
options root=UUID=\$ROOT_UUID rw quiet splash loglevel=3
ENTRY

# Root password
echo "root:${PASSWORD}" | chpasswd

# User creation
useradd -m -G wheel -s /bin/bash $USERNAME
echo "${USERNAME}:${PASSWORD}" | chpasswd
echo "%wheel ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/999_lobby

# Enable NetworkManager and SSH
systemctl enable NetworkManager
systemctl enable sshd
EOF

# --- Download modular installation scripts and assets ---
mkdir -p /mnt/root/scripts/{modules,configs/plymouth}

# Download main scripts
curl -sSL https://raw.githubusercontent.com/kenzie/lobby-arch/main/scripts/post-install.sh -o /mnt/root/scripts/post-install.sh
curl -sSL https://raw.githubusercontent.com/kenzie/lobby-arch/main/scripts/lobby.sh -o /mnt/root/scripts/lobby.sh

# Download modules
curl -sSL https://raw.githubusercontent.com/kenzie/lobby-arch/main/scripts/modules/01-autologin.sh -o /mnt/root/scripts/modules/01-autologin.sh
curl -sSL https://raw.githubusercontent.com/kenzie/lobby-arch/main/scripts/modules/02-hyprland.sh -o /mnt/root/scripts/modules/02-hyprland.sh
curl -sSL https://raw.githubusercontent.com/kenzie/lobby-arch/main/scripts/modules/03-plymouth.sh -o /mnt/root/scripts/modules/03-plymouth.sh
curl -sSL https://raw.githubusercontent.com/kenzie/lobby-arch/main/scripts/modules/04-auto-updates.sh -o /mnt/root/scripts/modules/04-auto-updates.sh
curl -sSL https://raw.githubusercontent.com/kenzie/lobby-arch/main/scripts/modules/99-cleanup.sh -o /mnt/root/scripts/modules/99-cleanup.sh

# Download configuration files
curl -sSL https://raw.githubusercontent.com/kenzie/lobby-arch/main/scripts/configs/hyprland.conf -o /mnt/root/scripts/configs/hyprland.conf
curl -sSL https://raw.githubusercontent.com/kenzie/lobby-arch/main/scripts/configs/start-wallpaper.sh -o /mnt/root/scripts/configs/start-wallpaper.sh
curl -sSL https://raw.githubusercontent.com/kenzie/lobby-arch/main/scripts/configs/plymouth/route19.plymouth -o /mnt/root/scripts/configs/plymouth/route19.plymouth
curl -sSL https://raw.githubusercontent.com/kenzie/lobby-arch/main/scripts/configs/plymouth/route19.script -o /mnt/root/scripts/configs/plymouth/route19.script

# Make scripts executable
chmod +x /mnt/root/scripts/*.sh /mnt/root/scripts/modules/*.sh

# Download logo asset
mkdir -p /mnt/root/assets
curl -sSL https://raw.githubusercontent.com/kenzie/lobby-arch/main/assets/route19-logo.png -o /mnt/root/assets/route19-logo.png

# --- Create systemd service to run post-install automatically on first boot ---
cat > /mnt/etc/systemd/system/post-install.service <<EOF
[Unit]
Description=Post Install Setup
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/root/scripts/post-install.sh
RemainAfterExit=no
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

arch-chroot /mnt systemctl enable post-install.service

# --- Unmount and finish ---
umount -R /mnt
echo "==> Installation complete. Reboot now. The system will auto-login and launch Hyprland with Plymouth splash."
