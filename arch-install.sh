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

# --- Download modular installation scripts and assets ---
echo "==> Downloading installation scripts and assets..."
mkdir -p /mnt/root/scripts/{modules,configs/plymouth}

# Function to download with error checking
download_file() {
    local url="$1"
    local output="$2"
    local max_retries=3
    local retry_delay=5
    
    for attempt in $(seq 1 $max_retries); do
        echo "Downloading $(basename "$output")... (attempt $attempt/$max_retries)"
        if curl -sSL --fail --connect-timeout 30 --max-time 300 "$url" -o "$output"; then
            echo "✓ Successfully downloaded $(basename "$output")"
            return 0
        else
            echo "✗ Failed to download $(basename "$output")"
            if [[ $attempt -lt $max_retries ]]; then
                echo "Retrying in ${retry_delay}s..."
                sleep $retry_delay
                retry_delay=$((retry_delay * 2))
            fi
        fi
    done
    
    echo "ERROR: Failed to download $url after $max_retries attempts"
    return 1
}

# Download main scripts
download_file "https://raw.githubusercontent.com/kenzie/lobby-arch/main/scripts/post-install.sh" "/mnt/root/scripts/post-install.sh" || exit 1
download_file "https://raw.githubusercontent.com/kenzie/lobby-arch/main/scripts/lobby.sh" "/mnt/root/scripts/lobby.sh" || exit 1

# Download modules
download_file "https://raw.githubusercontent.com/kenzie/lobby-arch/main/scripts/modules/02-kiosk.sh" "/mnt/root/scripts/modules/02-kiosk.sh" || exit 1
download_file "https://raw.githubusercontent.com/kenzie/lobby-arch/main/scripts/modules/03-plymouth.sh" "/mnt/root/scripts/modules/03-plymouth.sh" || exit 1
download_file "https://raw.githubusercontent.com/kenzie/lobby-arch/main/scripts/modules/04-auto-updates.sh" "/mnt/root/scripts/modules/04-auto-updates.sh" || exit 1
download_file "https://raw.githubusercontent.com/kenzie/lobby-arch/main/scripts/modules/05-monitoring.sh" "/mnt/root/scripts/modules/05-monitoring.sh" || exit 1
download_file "https://raw.githubusercontent.com/kenzie/lobby-arch/main/scripts/modules/06-scheduler.sh" "/mnt/root/scripts/modules/06-scheduler.sh" || exit 1
download_file "https://raw.githubusercontent.com/kenzie/lobby-arch/main/scripts/modules/99-cleanup.sh" "/mnt/root/scripts/modules/99-cleanup.sh" || exit 1

# Download configuration files
download_file "https://raw.githubusercontent.com/kenzie/lobby-arch/main/scripts/configs/plymouth/route19.plymouth" "/mnt/root/scripts/configs/plymouth/route19.plymouth" || exit 1
download_file "https://raw.githubusercontent.com/kenzie/lobby-arch/main/scripts/configs/plymouth/route19.script" "/mnt/root/scripts/configs/plymouth/route19.script" || exit 1

# Download logo asset
mkdir -p /mnt/root/assets
download_file "https://raw.githubusercontent.com/kenzie/lobby-arch/main/assets/route19-logo.png" "/mnt/root/assets/route19-logo.png" || exit 1

# Make scripts executable
chmod +x /mnt/root/scripts/*.sh /mnt/root/scripts/modules/*.sh

# Verify all critical files were downloaded
echo "==> Verifying downloaded files..."
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

echo "✓ All critical installation files downloaded successfully"

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
echo "==> Installation complete. Reboot now. The system will launch Cage kiosk with Plymouth splash."
