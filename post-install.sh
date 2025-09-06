#!/usr/bin/env bash
set -euo pipefail

echo "==> Running post-install setup..."

# Install AUR helper yay
pacman -S --needed --noconfirm git base-devel
cd /tmp
git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si --noconfirm

# Install Plymouth from AUR
yay -S --noconfirm plymouth

# Setup Route 19 theme
mkdir -p /usr/share/plymouth/themes/route19
cp /tmp/route19-logo.png /usr/share/plymouth/themes/route19/

cat > /usr/share/plymouth/themes/route19/route19.plymouth <<EOF
[Plymouth Theme]
Name=Route19
Description=Route19 boot splash
ModuleName=script
[script]
ScriptFile=/usr/share/plymouth/themes/route19/route19.script
EOF

cat > /usr/share/plymouth/themes/route19/route19.script <<EOF
plymouth.image_display("/usr/share/plymouth/themes/route19/route19-logo.png")
EOF

# Activate theme and rebuild initramfs
plymouth-set-default-theme -R route19

# Disable service and remove script
systemctl disable post-install.service
rm -f /tmp/post-install.sh

echo "==> Post-install complete. Reboot to see Route 19 splash."
