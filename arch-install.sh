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

# --- Create systemd service to run post-install automatically on first boot ---
echo "==> Creating post-install service..."

# Ensure systemd system directory exists
mkdir -p /mnt/etc/systemd/system

# Create the service file with explicit error checking
cat > /mnt/etc/systemd/system/post-install.service << 'EOF'
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

# Verify the service file was created successfully
if [[ ! -f /mnt/etc/systemd/system/post-install.service ]]; then
    echo "ERROR: Failed to create post-install service file"
    exit 1
fi

echo "==> Service file created successfully"

# Enable the service in chroot
echo "==> Enabling post-install service..."
arch-chroot /mnt systemctl enable post-install.service

# Verify the service was enabled
if ! arch-chroot /mnt systemctl is-enabled post-install.service >/dev/null 2>&1; then
    echo "ERROR: Failed to enable post-install service"
    exit 1
fi

echo "✓ Post-install service created and enabled successfully"

# --- Unmount and finish ---
umount -R /mnt
echo "==> Installation complete. Reboot now. The system will launch Cage kiosk with Plymouth splash."
