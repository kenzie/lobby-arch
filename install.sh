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

# Set default timezone and locale
TIMEZONE="America/Halifax"
LOCALE="en_US.UTF-8"

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
    base-devel openssh rng-tools curl bc \
    dbus \
    ttf-cascadia-code-nerd inter-font cairo freetype2 \
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

# Enable NetworkManager, SSH, and DBUS
systemctl enable NetworkManager
systemctl enable sshd
systemctl enable dbus
EOF

# --- Clone lobby-arch repository ---
echo "==> Cloning lobby-arch repository..."

# Install git if not present
if ! command -v git >/dev/null 2>&1;
    echo "Installing git and GitHub CLI..."
    arch-chroot /mnt pacman -S --noconfirm git github-cli
fi

# Clone the repository directly to /home/lobby/lobby-arch
if ! arch-chroot /mnt sudo -u lobby git clone https://github.com/kenzie/lobby-arch.git /home/lobby/lobby-arch; then
    echo "ERROR: Failed to clone repository"
    exit 1
fi

# Make scripts executable
echo "==> Making scripts executable..."
arch-chroot /mnt find /home/lobby/lobby-arch -name "*.sh" -type f -exec chmod +x {} \;

# Verify git repository is properly set up
echo "==> Verifying git repository setup..."
if arch-chroot /mnt test -d /home/lobby/lobby-arch/.git; then
    echo "✓ Git repository initialized"
    # Set git config for lobby system
    arch-chroot /mnt sudo -u lobby git -C /home/lobby/lobby-arch config --local user.name "Lobby System"
    arch-chroot /mnt sudo -u lobby git -C /home/lobby/lobby-arch config --local user.email "lobby@lobby-system"
    arch-chroot /mnt sudo -u lobby git -C /home/lobby/lobby-arch config --local pull.rebase false
else
    echo "✗ ERROR: Git repository not properly initialized"
    exit 1
fi

# Verify critical files exist
echo "==> Verifying installation files..."
critical_files=(
    "/mnt/home/lobby/lobby-arch/post-install.sh"
    "/mnt/home/lobby/lobby-arch/lobby.sh"
    "/mnt/home/lobby/lobby-arch/modules/10-plymouth.sh"
    "/mnt/home/lobby/lobby-arch/config/plymouth/logo.png"
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
if ! arch-chroot /mnt env CHROOT_INSTALL=1 /home/lobby/lobby-arch/post-install.sh; then
    echo "ERROR: Post-install setup failed"
    exit 1
fi

echo "✓ Post-install setup completed successfully"

# --- Unmount and finish ---
umount -R /mnt
echo "==> Installation complete. Reboot now. The system will launch Hyprland kiosk with Plymouth splash."
