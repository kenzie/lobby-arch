echo "==> Installing Plymouth splash..."
pacman -Sy --noconfirm plymouth plymouth-theme-spinner cdrtools

# Route 19 logo
THEME_DIR=/usr/share/plymouth/themes/route19
mkdir -p $THEME_DIR
curl -sSL https://www.route19.com/assets/images/image01.png?v=fa76ddff -o $THEME_DIR/logo.png

# Custom theme
cat > $THEME_DIR/route19.plymouth <<EOF
[Plymouth Theme]
Name=Route19
Description=Route 19 splash theme
ModuleName=script

[script]
ImageDir=$THEME_DIR
ScriptFile=$THEME_DIR/route19.script
EOF

cat > $THEME_DIR/route19.script <<'EOF'
plymouth_set_background_image("logo.png");
EOF

# Set default theme and rebuild initramfs
plymouth-set-default-theme -R route19
