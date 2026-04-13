#!/usr/bin/env bash
set -euo pipefail

# Generate .tag so wezterm-version/build.rs picks up a consistent
# version string for all binaries (wezterm, wezterm-gui, wezterm-mux-server).
# Set TAG_SUFFIX env var to append a custom postfix (e.g. TAG_SUFFIX=sakayk).
TAG_NAME="$(date +%Y%m%d-%H%M%S)-$(git -c core.abbrev=8 rev-parse --short=8 HEAD 2>/dev/null || echo manual)${TAG_SUFFIX:+-${TAG_SUFFIX}}"
printf '%s\n' "$TAG_NAME" > .tag
echo "=== Tag: ${TAG_NAME} ==="

echo "=== Building WezTerm release binaries ==="
cargo build --release \
  -p wezterm-gui \
  -p wezterm \
  -p wezterm-mux-server \
  -p strip-ansi-escapes

echo "=== Assembling .deb package (tag: ${TAG_NAME}) ==="
rm -rf pkg/debian
mkdir -p pkg/debian/{usr/bin,DEBIAN}
mkdir -p pkg/debian/usr/share/{applications,icons/hicolor/128x128/apps,metainfo}
mkdir -p pkg/debian/usr/share/{bash-completion/completions,zsh/functions/Completion/Unix}
mkdir -p pkg/debian/usr/share/nautilus-python/extensions
mkdir -p pkg/debian/etc/profile.d

# Binaries
install -Dsm755 -t pkg/debian/usr/bin target/release/wezterm-mux-server
install -Dsm755 -t pkg/debian/usr/bin target/release/wezterm-gui
install -Dsm755 -t pkg/debian/usr/bin target/release/wezterm
install -Dm755  -t pkg/debian/usr/bin assets/open-wezterm-here
install -Dsm755 -t pkg/debian/usr/bin target/release/strip-ansi-escapes

# Assets
install -Dm644 assets/icon/terminal.png pkg/debian/usr/share/icons/hicolor/128x128/apps/org.wezfurlong.wezterm.png
install -Dm644 assets/wezterm.desktop pkg/debian/usr/share/applications/org.wezfurlong.wezterm.desktop
install -Dm644 assets/wezterm.appdata.xml pkg/debian/usr/share/metainfo/org.wezfurlong.wezterm.appdata.xml
install -Dm644 assets/wezterm-nautilus.py pkg/debian/usr/share/nautilus-python/extensions/wezterm-nautilus.py
install -Dm644 assets/shell-completion/bash pkg/debian/usr/share/bash-completion/completions/wezterm
install -Dm644 assets/shell-completion/zsh pkg/debian/usr/share/zsh/functions/Completion/Unix/_wezterm
install -Dm644 assets/shell-integration/* -t pkg/debian/etc/profile.d

# Control file
ARCH=$(dpkg-architecture -q DEB_BUILD_ARCH_CPU)
cat > pkg/debian/DEBIAN/control <<CTRL
Package: wezterm
Version: ${TAG_NAME}
Architecture: ${ARCH}
Maintainer: Wez Furlong <wez@wezfurlong.org>
Section: utils
Priority: optional
Homepage: https://wezterm.org/
Provides: x-terminal-emulator
Description: Wez's Terminal Emulator.
 wezterm is a terminal emulator with support for modern features
 such as fonts with ligatures, hyperlinks, tabs and multiple windows.
CTRL

# Auto-detect shared library dependencies
deps=$(cd pkg && dpkg-shlibdeps -O \
  -e debian/usr/bin/wezterm-gui \
  -e debian/usr/bin/wezterm \
  -e debian/usr/bin/wezterm-mux-server \
  -e debian/usr/bin/strip-ansi-escapes 2>/dev/null || true)
if [ -n "$deps" ]; then
  echo "$deps" | sed 's/shlibs:Depends=/Depends: /' >> pkg/debian/DEBIAN/control
fi

# postinst
cat > pkg/debian/DEBIAN/postinst <<'SCRIPT'
#!/bin/sh
set -e
if [ "$1" = "configure" ] ; then
    update-alternatives --install /usr/bin/x-terminal-emulator x-terminal-emulator /usr/bin/open-wezterm-here 20
fi
SCRIPT
chmod 0755 pkg/debian/DEBIAN/postinst

# prerm
cat > pkg/debian/DEBIAN/prerm <<'SCRIPT'
#!/bin/sh
set -e
if [ "$1" = "remove" ]; then
    update-alternatives --remove x-terminal-emulator /usr/bin/open-wezterm-here
fi
SCRIPT
chmod 0755 pkg/debian/DEBIAN/prerm

# Build .deb
DISTRO=$(lsb_release -is 2>/dev/null || echo Linux)
RELEASE=$(lsb_release -rs 2>/dev/null || echo unknown)
DEB_NAME="wezterm-${TAG_NAME}.${DISTRO}.${RELEASE}.deb"

fakeroot dpkg-deb --build pkg/debian "/output/${DEB_NAME}"

echo "=== Done: /output/${DEB_NAME} ==="
