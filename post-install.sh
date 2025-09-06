#!/usr/bin/env bash
set -euo pipefail

echo "==> Installing AUR helper yay..."
pacman -S --needed --noconfirm git base-devel
cd /tmp
git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si --noconfirm

echo "==> Installing Plymouth from AUR..."
yay -S --noconfirm plymouth

echo "==> Setting up Route 19 theme..."
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

echo "==> Activating Plymouth theme..."
plymouth-set-default-theme -R route19
echo "==> Plymouth setup complete. Reboot to see Route 19 splash."
