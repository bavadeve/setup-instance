#!/usr/bin/env bash
set -euo pipefail

# Installs:
# - zsh + oh-my-zsh
# - your .zshrc + functions
# - ImageMagick 7 from source
#
# Assumptions:
# - ComfyUI & CUDA already installed (as per your Vast template)
#
# Env:
#   IM_VERSION=7.1.1-38 (optional)
#   PREFIX=$HOME/.local  (optional)

IM_VERSION="${IM_VERSION:-7.1.1-38}"
PREFIX="${PREFIX:-$HOME/.local}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Installing base packages"
if command -v apt-get >/dev/null 2>&1; then
  sudo apt-get update
  sudo apt-get install -y \
    zsh git curl wget rsync ca-certificates \
    build-essential pkg-config \
    autoconf automake libtool \
    zlib1g-dev libbz2-dev liblzma-dev \
    libjpeg-dev libpng-dev libtiff-dev libwebp-dev \
    libheif-dev libde265-dev libopenjp2-7-dev \
    liblcms2-dev liblqr-1-0-dev \
    libfreetype6-dev libfontconfig1-dev \
    libx11-dev libxext-dev libxt-dev \
    libfftw3-dev \
    libraw-dev \
    aria2 || true
else
  echo "ERROR: This script currently supports apt-get based systems only."
  exit 1
fi

echo "==> Installing oh-my-zsh (non-interactive)"
if [ ! -d "$HOME/.oh-my-zsh" ]; then
  RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
else
  echo "    oh-my-zsh already present"
fi

echo "==> Installing custom zsh config"
mkdir -p "$HOME/.config/vast-bootstrap"
cp -f "$REPO_ROOT/zshrc/functions.zsh" "$HOME/.config/vast-bootstrap/functions.zsh"
cp -f "$REPO_ROOT/zshrc/.zshrc" "$HOME/.zshrc"

echo "==> Building ImageMagick ${IM_VERSION} from source into ${PREFIX}"
mkdir -p "$HOME/.cache/imagemagick-src"
cd "$HOME/.cache/imagemagick-src"

TARBALL="ImageMagick-${IM_VERSION}.tar.gz"
URL="https://download.imagemagick.org/ImageMagick/download/releases/${TARBALL}"

if [ ! -f "$TARBALL" ]; then
  echo "    Downloading $URL"
  curl -fL "$URL" -o "$TARBALL"
fi

rm -rf "ImageMagick-${IM_VERSION}"
tar -xzf "$TARBALL"
cd "ImageMagick-${IM_VERSION}"

./configure \
  --prefix="$PREFIX" \
  --disable-static \
  --with-modules \
  --with-quantum-depth=16 \
  --with-magick-plus-plus=yes

make -j"$(nproc)"
make install

echo "==> Verifying ImageMagick install"
"$PREFIX/bin/magick" -version || true

echo "==> Ensuring $PREFIX/bin is on PATH (for future shells)"
if ! grep -q "$PREFIX/bin" "$HOME/.profile" 2>/dev/null; then
  echo "export PATH=\"$PREFIX/bin:\$PATH\"" >> "$HOME/.profile"
fi

echo "==> Done."
echo "Next:"
echo "  source ~/.zshrc"
echo "  ./scripts/install_custom_nodes.sh /workspace/vast-private/custom_nodes.txt"
echo "  ./scripts/download_models.sh /workspace/vast-private/models"
