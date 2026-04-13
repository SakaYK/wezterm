# Building WezTerm with Podman

This guide explains how to compile WezTerm using [Podman](https://podman.io/) without
needing to install a Rust toolchain or any system development libraries on your host OS.

## Prerequisites

- [Podman](https://podman.io/getting-started/installation) installed
- Internet access (to pull the base image and download crates on first build)

---

## 1. Build the Builder Image

Create a container image that contains Rust and all required system libraries.
You only need to do this **once** (or when you want to update the toolchain).

```bash
podman build -t wezterm-builder - <<'EOF'
FROM docker.io/rust:latest

RUN apt-get update && apt-get install -y \
    bsdutils \
    cmake \
    dpkg-dev \
    fakeroot \
    gcc \
    g++ \
    libegl1-mesa-dev \
    libssl-dev \
    libfontconfig1-dev \
    libwayland-dev \
    libx11-xcb-dev \
    libxcb-ewmh-dev \
    libxcb-icccm4-dev \
    libxcb-image0-dev \
    libxcb-keysyms1-dev \
    libxcb-randr0-dev \
    libxcb-render0-dev \
    libxcb-xkb-dev \
    libxkbcommon-dev \
    libxkbcommon-x11-dev \
    libxcb-util-dev \
    lsb-release \
    python3 \
    xdg-utils \
    xorg-dev \
    pkg-config \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build
EOF
```

---

## 2. (Optional) Create a Cargo Registry Cache

Reuse downloaded crates across builds to avoid re-downloading them every time.

```bash
mkdir -p ~/.cache/wezterm-cargo-registry
```

---

## 3. Compile

### Release build (recommended)

Produces optimized, stripped binaries equivalent to the official packages.

```bash
podman run --rm \
  -v "$(pwd)":/build:z \
  -v ~/.cache/wezterm-cargo-registry:/usr/local/cargo/registry:z \
  wezterm-builder \
  cargo build --release -p wezterm -p wezterm-gui -p wezterm-mux-server
```

### Debug build (faster to compile, larger binaries)

```bash
podman run --rm \
  -v "$(pwd)":/build:z \
  -v ~/.cache/wezterm-cargo-registry:/usr/local/cargo/registry:z \
  wezterm-builder \
  cargo build -p wezterm -p wezterm-gui -p wezterm-mux-server
```

---

## 4. Output Binaries

After a successful build, the binaries are located at:

| Binary | Path |
|--------|------|
| `wezterm` | `target/release/wezterm` |
| `wezterm-gui` | `target/release/wezterm-gui` |
| `wezterm-mux-server` | `target/release/wezterm-mux-server` |

---

## 5. Install

Copy the binaries to your system:

```bash
sudo cp target/release/wezterm \
        target/release/wezterm-gui \
        target/release/wezterm-mux-server \
        /usr/local/bin/
```

---

## 6. Build a `.deb` Package (Ubuntu/Debian)

If you prefer to install via a `.deb` package instead of copying binaries manually,
you can build and package everything inside the container.

### Using a distro-matching base image

For `.deb` packages, it is recommended to use a base image that matches your target
distribution so that `dpkg-shlibdeps` generates the correct library dependencies.
For example, for Ubuntu 26.04 (Resolute):

```bash
podman build -t wezterm-deb-builder - <<'EOF'
FROM docker.io/ubuntu:26.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    curl build-essential \
    bsdutils cmake dpkg-dev fakeroot gcc g++ git \
    libegl1-mesa-dev libssl-dev libfontconfig1-dev \
    libwayland-dev libx11-xcb-dev libxcb-ewmh-dev \
    libxcb-icccm4-dev libxcb-image0-dev libxcb-keysyms1-dev \
    libxcb-randr0-dev libxcb-render0-dev libxcb-xkb-dev \
    libxkbcommon-dev libxkbcommon-x11-dev libxcb-util-dev \
    lsb-release python3 xdg-utils xorg-dev pkg-config \
    && rm -rf /var/lib/apt/lists/*

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"

WORKDIR /build
EOF
```

Replace `ubuntu:26.04` with the appropriate tag for your target distribution
(e.g. `ubuntu:24.04`, `debian:bookworm`).

### Build and package

```bash
podman run --rm \
  -v "$(pwd)":/build:z \
  -v ~/.cache/wezterm-cargo-registry:/root/.cargo/registry:z \
  wezterm-deb-builder \
  bash -c '
    set -e

    cargo build --release \
      -p wezterm-gui \
      -p wezterm \
      -p wezterm-mux-server \
      -p strip-ansi-escapes

    TAG_NAME="$(date +%Y%m%d)-$(git rev-parse --short HEAD 2>/dev/null || echo manual)"

    rm -rf pkg/debian
    mkdir -p pkg/debian/{usr/bin,DEBIAN}
    mkdir -p pkg/debian/usr/share/{applications,icons/hicolor/128x128/apps,metainfo}
    mkdir -p pkg/debian/usr/share/{bash-completion/completions,zsh/functions/Completion/Unix}
    mkdir -p pkg/debian/usr/share/nautilus-python/extensions
    mkdir -p pkg/debian/etc/profile.d

    install -Dsm755 -t pkg/debian/usr/bin target/release/wezterm-mux-server
    install -Dsm755 -t pkg/debian/usr/bin target/release/wezterm-gui
    install -Dsm755 -t pkg/debian/usr/bin target/release/wezterm
    install -Dm755  -t pkg/debian/usr/bin assets/open-wezterm-here
    install -Dsm755 -t pkg/debian/usr/bin target/release/strip-ansi-escapes

    install -Dm644 assets/icon/terminal.png pkg/debian/usr/share/icons/hicolor/128x128/apps/org.wezfurlong.wezterm.png
    install -Dm644 assets/wezterm.desktop pkg/debian/usr/share/applications/org.wezfurlong.wezterm.desktop
    install -Dm644 assets/wezterm.appdata.xml pkg/debian/usr/share/metainfo/org.wezfurlong.wezterm.appdata.xml
    install -Dm644 assets/wezterm-nautilus.py pkg/debian/usr/share/nautilus-python/extensions/wezterm-nautilus.py
    install -Dm644 assets/shell-completion/bash pkg/debian/usr/share/bash-completion/completions/wezterm
    install -Dm644 assets/shell-completion/zsh pkg/debian/usr/share/zsh/functions/Completion/Unix/_wezterm
    install -Dm644 assets/shell-integration/* -t pkg/debian/etc/profile.d

    cat > pkg/debian/DEBIAN/control <<CTRL
Package: wezterm
Version: ${TAG_NAME}
Architecture: $(dpkg-architecture -q DEB_BUILD_ARCH_CPU)
Maintainer: Wez Furlong <wez@wezfurlong.org>
Section: utils
Priority: optional
Homepage: https://wezterm.org/
Provides: x-terminal-emulator
Description: Wez'\''s Terminal Emulator.
 wezterm is a terminal emulator with support for modern features
 such as fonts with ligatures, hyperlinks, tabs and multiple windows.
CTRL

    deps=$(cd pkg && dpkg-shlibdeps -O -e debian/usr/bin/wezterm-gui \
      -e debian/usr/bin/wezterm -e debian/usr/bin/wezterm-mux-server \
      -e debian/usr/bin/strip-ansi-escapes 2>/dev/null || true)
    if [ -n "$deps" ]; then
      echo "$deps" | sed "s/shlibs:Depends=/Depends: /" >> pkg/debian/DEBIAN/control
    fi

    cat > pkg/debian/DEBIAN/postinst <<SCRIPT
#!/bin/sh
set -e
if [ "\$1" = "configure" ] ; then
    update-alternatives --install /usr/bin/x-terminal-emulator x-terminal-emulator /usr/bin/open-wezterm-here 20
fi
SCRIPT
    chmod 0755 pkg/debian/DEBIAN/postinst

    cat > pkg/debian/DEBIAN/prerm <<SCRIPT
#!/bin/sh
set -e
if [ "\$1" = "remove" ]; then
    update-alternatives --remove x-terminal-emulator /usr/bin/open-wezterm-here
fi
SCRIPT
    chmod 0755 pkg/debian/DEBIAN/prerm

    DISTRO=$(lsb_release -is 2>/dev/null || echo Linux)
    RELEASE=$(lsb_release -rs 2>/dev/null || echo unknown)
    fakeroot dpkg-deb --build pkg/debian "wezterm-${TAG_NAME}.${DISTRO}.${RELEASE}.deb"
    echo "=== Package built: wezterm-${TAG_NAME}.${DISTRO}.${RELEASE}.deb ==="
  '
```

The `.deb` file will be created in the project root directory on your host. Install it with:

```bash
sudo dpkg -i wezterm-*.deb
sudo apt-get install -f   # resolve any missing dependencies
```

### Using Docker Compose / Podman Compose

The `manual-build/` directory provides a ready-made multi-distro setup.
Pick the target you want to build:

| Service | Distro | Package |
|---------|--------|---------|
| `ubuntu-26.04` | Ubuntu 26.04 (Resolute) | `.deb` |
| `ubuntu-24.04` | Ubuntu 24.04 (Noble) | `.deb` |
| `ubuntu-22.04` | Ubuntu 22.04 (Jammy) | `.deb` |
| `debian-12` | Debian 12 (Bookworm) | `.deb` |
| `debian-11` | Debian 11 (Bullseye) | `.deb` |
| `fedora-41` | Fedora 41 | `.rpm` |
| `fedora-40` | Fedora 40 | `.rpm` |
| `centos-stream9` | CentOS Stream 9 | `.rpm` |

Build for a specific distro:

```bash
cd manual-build
podman-compose up --build ubuntu-26.04
```

Build for multiple distros at once:

```bash
podman-compose up --build ubuntu-26.04 fedora-41 debian-12
```

Build all distros:

```bash
podman-compose up --build
```

All packages are written to `manual-build/output/`. Install with:

```bash
# Debian/Ubuntu
sudo dpkg -i manual-build/output/wezterm-*.deb
sudo apt-get install -f

# Fedora/CentOS
sudo dnf install manual-build/output/wezterm-*.rpm
```

---

## Notes

- The `:z` volume flag sets the correct SELinux label so Podman can access the files.
  If you are not using SELinux, you can omit it.
- The cargo registry cache (`~/.cache/wezterm-cargo-registry`) is optional but
  significantly speeds up subsequent builds by avoiding repeated crate downloads.
- The `strip = true` flag is set in `Cargo.toml`'s `[profile.release]`, so release
  binaries are automatically stripped of debug symbols — no manual `strip` step needed.
