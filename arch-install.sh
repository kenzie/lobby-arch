#!/usr/bin/env bash
set -euo pipefail

# === USER CONFIGURATION ===
DISK="/dev/sda"             # TARGET DISK, change if needed
HOSTNAME="lobby-m75q"
USERNAME="lobby"
PASSWORD="changeMe!"        # change later
TIMEZONE="America/Halifax"
LOCALE="en_US.UTF-8"
EFI_SIZE="512MiB"
ROOT_PART="100%"             # rest of disk
GITHUB_SSH_KEY=""            # optional, deploy key
ROUTE19_LOGO_PATH="/path/to/route19-logo.png" # for plymouth

# === Partitioning ===
echo "==> Partitioning $DISK"
parted --script "$DISK" \
  mklabel gpt \
  mkpart primary fat32 1MiB $EFI_SIZE \
  set 1 esp on \
  mkpart primary ext4 $EFI_SIZE $ROOT_PART

EFI="${DISK}1"
ROOT="${DISK}2"

echo "==> Formatting partitions"
mkfs.fat -F32 "$EFI"
mkfs.ext4 -F "$ROOT"

echo "==> Mounting partitions"
mount "$ROOT" /mnt
mkdir -p /mnt/boot
mount "$EFI" /mnt/boot

# === Install base system ===
echo "==> Installing base packages"
pacstrap /mnt base linux linux-firmware vim networkmanager sudo git \
    base-devel openssh rng-tools

# Generate fstab
genfstab -U /mnt >> /mnt/etc/fstab

# === Chroot and configuration ===
echo "==> Entering chroot"
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
cat > /boot/loader/loader.conf <<LOADER
default  arch
timeout  3
console-mode max
editor  no
LOADER

cat > /boot/loader/entries/arch.conf <<ENTRY
title   Arch Linux
linux   /vmlinuz-linux
initrd  /initramfs-linux.img
options root=PARTLABEL=ROOT quiet splash loglevel=3
ENTRY

# Root password
echo "root:${PASSWORD}" | chpasswd

# User creation
useradd -m -G wheel -s /bin/bash $USERNAME
echo "${USERNAME}:${PASSWORD}" | chpasswd
echo "%wheel ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/999_lobby

# Enable NetworkManager
systemctl enable NetworkManager

# Essential packages for lobby system
pacman -Syu --noconfirm hyprland hyprpaper xorg-server \
    xdg-desktop-portal xdg-desktop-portal-wlr \
    chromium nginx git python python-pip rclone \
    plymouth plymouth-theme-spinner libcec cec-utils \
    nodejs npm

# SSH optional
systemctl enable sshd

EOF

# === Finish up ===
echo "==> Unmounting and rebooting"
umount -R /mnt
echo "Arch install complete. Reboot now and remove USB."
