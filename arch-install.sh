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

# --- Install base system + Cage + Plymouth (no spinner theme) ---
echo "==> Installing base packages..."
pacstrap /mnt base linux linux-firmware vim networkmanager sudo git \
    base-devel openssh rng-tools curl bc \
    cage seatd chromium xorg-xwayland \
    ttf-cascadia-code-nerd inter-font cairo freetype2 \
    nodejs npm \
    plymouth cdrtools \
    amd-ucode mesa vulkan-radeon libva-mesa-driver mesa-vdpau \
    wireless_tools wpa_supplicant

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
initrd  /amd-ucode.img
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

# --- Clone lobby-arch repository ---
echo "==> Cloning lobby-arch repository..."

# Install git if not present
if ! command -v git >/dev/null 2>&1; then
    echo "Installing git..."
    arch-chroot /mnt pacman -S --noconfirm git
fi

# Clone the repository to /mnt/root/scripts
if ! arch-chroot /mnt git clone https://github.com/kenzie/lobby-arch.git /root/lobby-arch-temp; then
    echo "ERROR: Failed to clone repository"
    exit 1
fi

# Move scripts directory to correct location
arch-chroot /mnt mv /root/lobby-arch-temp/scripts /root/scripts
arch-chroot /mnt mv /root/lobby-arch-temp/assets /root/assets

# Remove temporary clone directory but keep git metadata in scripts
arch-chroot /mnt mv /root/lobby-arch-temp/.git /root/scripts/.git
arch-chroot /mnt rm -rf /root/lobby-arch-temp

# Make scripts executable
arch-chroot /mnt chmod +x /root/scripts/*.sh /root/scripts/modules/*.sh

# Verify git repository is properly set up
echo "==> Verifying git repository setup..."
if arch-chroot /mnt test -d /root/scripts/.git; then
    echo "✓ Git repository initialized"
    # Set git config for lobby system
    arch-chroot /mnt git -C /root/scripts config --local user.name "Lobby System"
    arch-chroot /mnt git -C /root/scripts config --local user.email "lobby@lobby-system"
    arch-chroot /mnt git -C /root/scripts config --local pull.rebase false
else
    echo "✗ ERROR: Git repository not properly initialized"
    exit 1
fi

# Verify critical files exist
echo "==> Verifying installation files..."
critical_files=(
    "/mnt/root/scripts/post-install.sh"
    "/mnt/root/scripts/lobby.sh" 
    "/mnt/root/scripts/modules/02-kiosk.sh"
    "/mnt/root/assets/route19-logo.png"
)

for file in "${critical_files[@]}"; do
    if [[ -f "$file" && -s "$file" ]]; then
        echo "✓ $(basename "$file") verified"
    else
        echo "✗ ERROR: $(basename "$file") is missing or empty"
        exit 1
    fi
done

echo "✓ Repository cloned and verified successfully"

# --- Skip systemd service creation and run post-install directly ---
echo "==> Running post-install setup directly..."

# Instead of relying on systemd service that keeps failing,
# just run the post-install script directly in chroot
# Set CHROOT_INSTALL flag to skip network checks and systemd operations
if ! arch-chroot /mnt env CHROOT_INSTALL=1 /root/scripts/post-install.sh; then
    echo "ERROR: Post-install setup failed"
    exit 1
fi

echo "✓ Post-install setup completed successfully"

# --- Unmount and finish ---
umount -R /mnt
echo "==> Installation complete. Reboot now. The system will launch Cage kiosk with Plymouth splash."
