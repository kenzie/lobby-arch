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
[[ ! "$DISK" =~ ^/dev/ ]] && DISK="/dev/$DISK"
[[ ! -b "$DISK" ]] && echo "Error: $DISK not valid" && exit 1

echo "You selected $DISK. All data will be erased!"
echo -n "Are you sure? (y/N): "
read CONFIRM
[[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]] && echo "Aborting." && exit 1

# --- Prompt hostname/user ---
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

# --- Clean disk (NVMe-safe) ---
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

# --- Format & mount ---
mkfs.ext4 -F "$ROOT"
mkfs.fat -F32 "$EFI"

mount "$ROOT" /mnt
mkdir -p /mnt/boot
mount -t vfat "$EFI" /mnt/boot

# --- Install base system ---
echo "==> Installing base packages..."
pacstrap /mnt base linux linux-firmware vim networkmanager sudo git \
    base-devel openssh rng-tools curl \
    hyprland hyprpaper xorg-server \
    xdg-desktop-portal xdg-desktop-portal-wlr \
    chromium nginx git python python-pip rclone \
    nodejs npm

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
options root=PARTLABEL=ROOT quiet loglevel=3
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

# --- Copy post-install script ---
curl -sSL https://raw.githubusercontent.com/kenzie/lobby-arch/main/post-install-plymouth.sh -o /mnt/tmp/post-install-plymouth.sh
chmod +x /mnt/tmp/post-install-plymouth.sh

# --- Unmount and finish ---
umount -R /mnt
echo "==> Installation complete. Reboot and then log in to run post-install script:"
echo "sudo /tmp/post-install-plymouth.sh"
