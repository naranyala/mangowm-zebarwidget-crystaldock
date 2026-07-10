#!/bin/bash
# -------------------------------------------------------------------
# Zig 0.16.0 Installer Script
# Downloads Zig 0.16.0 for Linux x86_64 and installs it to ~/.local/bin
# -------------------------------------------------------------------

set -euo pipefail

ZIG_VERSION="0.16.0"
ZIG_TARBALL="zig-x86_64-linux-${ZIG_VERSION}.tar.xz"
ZIG_URL="https://ziglang.org/download/${ZIG_VERSION}/${ZIG_TARBALL}"
INSTALL_DIR="${HOME}/.local"
BIN_DIR="${INSTALL_DIR}/bin"

echo "==> Downloading Zig ${ZIG_VERSION}..."
curl -L --progress-bar "${ZIG_URL}" -o "/tmp/${ZIG_TARBALL}"

echo "==> Extracting to ${INSTALL_DIR}..."
mkdir -p "${INSTALL_DIR}"
tar -xf "/tmp/${ZIG_TARBALL}" -C "${INSTALL_DIR}"

# Remove old installation if exists
rm -rf "${INSTALL_DIR}/zig"
mv "${INSTALL_DIR}/zig-x86_64-linux-${ZIG_VERSION}" "${INSTALL_DIR}/zig"

# Symlink to bin
mkdir -p "${BIN_DIR}"
ln -sf "../zig/zig" "${BIN_DIR}/zig"

# Cleanup
rm -f "/tmp/${ZIG_TARBALL}"

echo ""
echo "✓ Zig ${ZIG_VERSION} successfully installed to ${BIN_DIR}/zig!"
echo "Make sure ${BIN_DIR} is in your PATH."
echo "You can check by running: ~/.local/bin/zig version"
