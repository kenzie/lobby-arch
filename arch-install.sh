#!/usr/bin/env bash
set -euo pipefail

echo "======================================="
echo "ARCH LOBBY INSTALLER (Interactive)"
echo "This will wipe the selected disk!"
echo "======================================="

# --- List available disks ---
echo "Available disks:"
lsblk -d -o NAME,SIZE,MODEL
echo

# --- Prompt for target disk ---
echo -n "Enter target disk: "
read DISK

# Ensure full /dev path
if [[ ! "$DISK" =~ ^/dev/ ]]; then
    DISK="/dev/$DISK"
fi

# Validate disk exists
if [[ ! -b "$DISK" ]]; then
    echo "Error: $DISK is not a valid block device."
    exit 1
fi

# --- Confirm disk wipe ---
echo "You selected $DISK. All data on this disk will be erased!"
echo -n "Are you sure? (y/N): "
read CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    echo "Aborting."
    exit 1
fi

# --- Prompt for hostname, user, password, timezone, locale ---
DEFAULT_HOSTNAME="lobby-screen"
DEFAULT_USER="lobby"

echo -n "New hostname (default $DEFAULT_HOSTNAME): "
read HOSTNAME
HOSTNAME=${HOSTNAME:-$DEFAULT_HOSTNAME}

echo -n "New username (default $DEFAULT_USER): "
read USERNAME
USERNAME=${USERNAME:-$DEFAULT_USER}

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

# --- Paths and partition sizes ---
EFI_SIZE="512MiB"
ROOT_PART="100%"
ROUTE19_LOGO="/tmp/route19-logo.png"

echo "==> Downloading Route 19 logo..."
curl -L -o "$ROUTE19_LOGO" "https://www.route19.com/assets/images/image01.png?v=fa76ddff"

# --- Partitioning ---
echo "==> Partitioning $DISK..."
parted --script "$DISK" \
  mklabel gpt \
  mkpart primary fat32 1MiB $EFI_SIZE \
  set 1 esp on \
  mkpart primary ext4 $EFI_SIZE $ROOT_PART

EFI="${DISK}1"
ROOT="${DISK}2"

echo "==> Formatting partitions..."
mkfs.fat -F32 "$EFI"
mkfs.ext4 -F "$ROOT"

echo "==> Mounting partitions..."
mount "$ROOT" /mnt
mkdir -p /mnt/boot
mount "$EFI" /mnt/boot

# --- Install base system ---
echo "==> Installing base packages..."
pacstrap /mnt base linux linux-firmware vim networkmanager sudo git \
    base-devel openssh rng-tools curl

echo "==> Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

# --- Chroot and configuration ---
echo "==> Entering chroot for configuration..."
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

# Install essential packages
pacman -Syu --noconfirm hyprland hyprpaper xorg-server \
    xdg-desktop-portal xdg-desktop-portal-wlr \
    chromium nginx git python python-pip rclone \
    plymouth plymouth-theme-spinner libcec cec-utils \
    nodejs npm curl

# Enable SSH
systemctl enable sshd

# Plymouth bootsplash with Route 19 logo
mkdir -p /usr/share/plymouth/themes/route19
cp "$ROUTE19_LOGO" /usr/share/plymouth/themes/route19/
plymouth-set-default-theme -R route19
mkinitcpio -P

EOF

# --- Finish up ---
echo "==> Unmounting partitions..."
umount -R /mnt

echo "==> Installation complete. Reboot and remove USB."
