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
mkfs.ext4 -F "$ROOT" -L ROOT       # Automatically sets root label
mkfs.fat -F32 "$EFI"               # FAT32 doesn't support e2label
fatlabel "$EFI" EFI                 # Set EFI label

# --- Mount ---
mount "$ROOT" /mnt
mkdir -p /mnt/boot
mount -t vfat "$EFI" /mnt/boot
