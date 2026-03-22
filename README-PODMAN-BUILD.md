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

## Notes

- The `:z` volume flag sets the correct SELinux label so Podman can access the files.
  If you are not using SELinux, you can omit it.
- The cargo registry cache (`~/.cache/wezterm-cargo-registry`) is optional but
  significantly speeds up subsequent builds by avoiding repeated crate downloads.
- The `strip = true` flag is set in `Cargo.toml`'s `[profile.release]`, so release
  binaries are automatically stripped of debug symbols — no manual `strip` step needed.
