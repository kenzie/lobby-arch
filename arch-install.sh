#!/usr/bin/env bash
set -euo pipefail

# === Interactive prompts ===
read -rp "Target disk (example /dev/sda) : " DISK
read -rp "New hostname: " HOSTNAME
read -rp "New username: " USERNAME
read -rsp "Password for new user: " PASSWORD
echo
read -rp "Timezone (default America/Halifax): " TIMEZONE
TIMEZONE=${TIMEZONE:-America/Halifax}
read -rp "Locale (default en_US.UTF-8): " LOCALE
LOCALE=${LOCALE:-en_US.UTF-8}

# === Paths ===
EFI_SIZE="512MiB"
ROOT_PART="100%"
ROUTE19_LOGO="/tmp/route19-logo.png"

# === Download Route 19 logo ===
echo "==> Downloading Route 19 logo..."
curl -L -o "$ROUTE19_LOGO" "https://www.route19.com/assets/images/image01.png?v=fa76ddff"

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

# Essential packages
pacman -Syu --noconfirm hyprland hyprpaper xorg-server \
    xdg-desktop-portal xdg-desktop-portal-wlr \
    chromium nginx git python python-pip rclone \
    plymouth plymouth-theme-spinner libcec cec-utils \
    nodejs npm curl

# SSH optional
systemctl enable sshd

# === Plymouth splash with Route 19 logo ===
mkdir -p /usr/share/plymouth/themes/route19
cp "$ROUTE19_LOGO" /usr/share/plymouth/themes/route19/
plymouth-set-default-theme -R route19
mkinitcpio -P

EOF

# === Finish up ===
umount -R /mnt
echo "==> Arch install complete. Reboot now and remove USB."
