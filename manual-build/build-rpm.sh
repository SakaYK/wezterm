#!/usr/bin/env bash
set -euo pipefail

# Generate .tag so wezterm-version/build.rs picks up a consistent
# version string for all binaries.
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

RPM_VERSION=$(echo "${TAG_NAME}" | tr - _)
DISTRO_ID=$(source /etc/os-release && echo "${ID}" | tr - _)
DISTRO_VER=$(source /etc/os-release && echo "${VERSION_ID}" | tr - _)
SPEC_RELEASE="1.${DISTRO_ID}${DISTRO_VER}"

echo "=== Assembling RPM package (${RPM_VERSION}, ${SPEC_RELEASE}) ==="

cat > wezterm.spec <<SPEC
Name: wezterm
Version: ${RPM_VERSION}
Release: ${SPEC_RELEASE}
Packager: Wez Furlong <wez@wezfurlong.org>
License: MIT
URL: https://wezterm.org/
Summary: Wez's Terminal Emulator.

%global debug_package %{nil}

%description
wezterm is a terminal emulator with support for modern features
such as fonts with ligatures, hyperlinks, tabs and multiple
windows.

%install
cd /build
mkdir -p %{buildroot}/usr/bin
mkdir -p %{buildroot}/etc/profile.d
mkdir -p %{buildroot}/etc/bash_completion.d
mkdir -p %{buildroot}/usr/share/zsh/site-functions
mkdir -p %{buildroot}/usr/share/icons/hicolor/128x128/apps
mkdir -p %{buildroot}/usr/share/applications
mkdir -p %{buildroot}/usr/share/metainfo
mkdir -p %{buildroot}/usr/share/nautilus-python/extensions

install -Dsm755 target/release/wezterm -t %{buildroot}/usr/bin
install -Dsm755 target/release/wezterm-gui -t %{buildroot}/usr/bin
install -Dsm755 target/release/wezterm-mux-server -t %{buildroot}/usr/bin
install -Dsm755 target/release/strip-ansi-escapes -t %{buildroot}/usr/bin
install -Dm755  assets/open-wezterm-here -t %{buildroot}/usr/bin
install -Dm644  assets/shell-integration/* -t %{buildroot}/etc/profile.d
install -Dm644  assets/shell-completion/bash %{buildroot}/etc/bash_completion.d/wezterm
install -Dm644  assets/shell-completion/zsh %{buildroot}/usr/share/zsh/site-functions/_wezterm
install -Dm644  assets/icon/terminal.png %{buildroot}/usr/share/icons/hicolor/128x128/apps/org.wezfurlong.wezterm.png
install -Dm644  assets/wezterm.desktop %{buildroot}/usr/share/applications/org.wezfurlong.wezterm.desktop
install -Dm644  assets/wezterm.appdata.xml %{buildroot}/usr/share/metainfo/org.wezfurlong.wezterm.appdata.xml
install -Dm644  assets/wezterm-nautilus.py %{buildroot}/usr/share/nautilus-python/extensions/wezterm-nautilus.py

%files
/usr/bin/wezterm
/usr/bin/wezterm-gui
/usr/bin/wezterm-mux-server
/usr/bin/strip-ansi-escapes
/usr/bin/open-wezterm-here
/etc/profile.d/*
/etc/bash_completion.d/wezterm
/usr/share/zsh/site-functions/_wezterm
/usr/share/icons/hicolor/128x128/apps/org.wezfurlong.wezterm.png
/usr/share/applications/org.wezfurlong.wezterm.desktop
/usr/share/metainfo/org.wezfurlong.wezterm.appdata.xml
/usr/share/nautilus-python/extensions/wezterm-nautilus.py*

%changelog
* $(date '+%a %b %d %Y') sakayk
- Local build ${TAG_NAME}
SPEC

rpmbuild -bb --rmspec wezterm.spec --verbose

# Copy RPMs to output
find "$(rpm --eval '%{_rpmdir}')" -name '*.rpm' -exec cp {} /output/ \;

echo "=== Done: RPM packages copied to /output/ ==="
