#!/usr/bin/env bash

# Script to download the FLTK (Fast Light Toolkit) source code into ./sources/fltk
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCES_DIR="${SCRIPT_DIR}/sources"
FLTK_DIR="${SOURCES_DIR}/fltk"
FLTK_REPO="https://github.com/fltk/fltk.git"
FLTK_TAG="release-1.4.5"

echo "========================================="
echo " Downloading FLTK Source Code"
echo "========================================="

# Create sources directory if it doesn't exist
mkdir -p "${SOURCES_DIR}"

if [ -d "${FLTK_DIR}" ]; then
    echo "[INFO] FLTK source already exists at: ${FLTK_DIR}"
    echo "[INFO] Updating to latest on tag ${FLTK_TAG}..."
    cd "${FLTK_DIR}"
    git fetch --tags
    git checkout "${FLTK_TAG}"
    echo "[OK] FLTK source updated."
else
    echo "[INFO] Cloning FLTK from ${FLTK_REPO}..."
    git clone "${FLTK_REPO}" "${FLTK_DIR}"
    cd "${FLTK_DIR}"
    echo "[INFO] Checking out release tag: ${FLTK_TAG}"
    git checkout "${FLTK_TAG}"
    echo "[OK] FLTK source cloned."
fi

echo ""
echo "========================================="
echo " FLTK source is ready at:"
echo "   ${FLTK_DIR}"
echo "========================================="
echo ""
echo "To build FLTK, you can run:"
echo "  cd ${FLTK_DIR}"
echo "  cmake -B build -DCMAKE_BUILD_TYPE=Release"
echo "  cmake --build build -j\$(nproc)"
echo "  sudo cmake --install build"
