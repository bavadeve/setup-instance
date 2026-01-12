#!/usr/bin/env bash
set -euo pipefail

# setup-instance install.sh
# - Installs base packages (zsh, git, curl, build deps)
# - Installs oh-my-zsh (non-interactive)
# - Installs your .zshrc + functions.zsh
# - Ensures ImageMagick >= IM_MIN_VERSION; otherwise builds the *latest* ImageMagick release from GitHub into ~/.local
# - Makes ImageMagick discoverable for:
#     * CLI checks (magick/convert in /usr/local/bin)
#     * Python bindings (wand can load libMagick*.so via ldconfig)
#
# Env overrides:
#   IM_MIN_VERSION=7.1.1
#   PREFIX=$HOME/.local
#   FORCE_IM_BUILD=1
#   GITHUB_TOKEN=...             # optional; avoids GitHub API rate limits

IM_MIN_VERSION="${IM_MIN_VERSION:-7.1.1}"
PREFIX="${PREFIX:-$HOME/.local}"
FORCE_IM_BUILD="${FORCE_IM_BUILD:-0}"

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
if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
  RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
else
  echo "    oh-my-zsh already present"
fi

echo "==> Installing custom zsh config"
mkdir -p "$HOME/.config/vast-bootstrap"
cp -f "$REPO_ROOT/zshrc/functions.zsh" "$HOME/.config/vast-bootstrap/functions.zsh"
cp -f "$REPO_ROOT/zshrc/.zshrc" "$HOME/.zshrc"

echo "==> Ensuring $PREFIX/bin is on PATH for future shells"
if ! grep -q "$PREFIX/bin" "$HOME/.profile" 2>/dev/null; then
  echo "export PATH=\"$PREFIX/bin:\$PATH\"" >> "$HOME/.profile"
fi

version_ge() {
  # true if $1 >= $2
  printf '%s\n%s\n' "$2" "$1" | sort -C -V
}

get_latest_imagemagick_tag() {
  local api="https://api.github.com/repos/ImageMagick/ImageMagick/releases/latest"
  local auth=()
  local tmp

  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    auth=(-H "Authorization: token ${GITHUB_TOKEN}")
  fi

  tmp="$(mktemp)"
  trap 'rm -f "$tmp"' RETURN

  curl -fsSL "${auth[@]}" "$api" -o "$tmp"

  grep -m1 '"tag_name"' "$tmp" \
    | sed -E 's/.*"tag_name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/'
}

download_imagemagick_src() {
  local tag="$1"
  local tarball="ImageMagick-${tag}.tar.gz"

  local url1="https://github.com/ImageMagick/ImageMagick/releases/download/${tag}/${tarball}"
  local url2="https://github.com/ImageMagick/ImageMagick/archive/refs/tags/${tag}.tar.gz"

  echo "==> Downloading ImageMagick source from GitHub (tag: ${tag})"
  rm -f "$tarball" "${tag}.tar.gz" 2>/dev/null || true

  if wget -q --show-progress -O "$tarball" "$url1"; then
    echo "==> Downloaded release asset"
    tar xf "$tarball"
    return 0
  fi

  echo "==> Release asset not found; falling back to tag archive"
  wget -q --show-progress -O "${tag}.tar.gz" "$url2"
  tar xf "${tag}.tar.gz"
}

ensure_imagemagick_system_visibility() {
  local prefix="$1"

  echo "==> Making ImageMagick discoverable system-wide"

  # 1) Ensure dynamic linker can find libs for Python 'wand' + any subprocesses
  local conf="/etc/ld.so.conf.d/imagemagick-local.conf"
  {
    echo "${prefix}/lib"
    echo "${prefix}/lib64"
  } | sudo tee "$conf" >/dev/null

  sudo ldconfig

  # 2) Ensure CLI checks can find magick/convert regardless of PATH quirks
  if [[ -x "${prefix}/bin/magick" ]]; then
    sudo ln -sf "${prefix}/bin/magick" /usr/local/bin/magick
    sudo ln -sf "${prefix}/bin/magick" /usr/local/bin/convert
  fi
}

ensure_wand_available() {
  # Try to install wand into the *current* python environment (best effort)
  # This is safe even if you don't use the node; it's lightweight.
  if command -v python >/dev/null 2>&1; then
    echo "==> Ensuring Python 'wand' is installed (best effort)"
    python -m pip install --no-cache-dir -q wand || true
  fi
}

need_im_build=true

if [[ "$FORCE_IM_BUILD" == "1" ]]; then
  echo "==> FORCE_IM_BUILD=1 set; will build ImageMagick from source"
elif command -v magick >/dev/null 2>&1; then
  IM_VERSION_INSTALLED="$(magick -version | head -n1 | awk '{print $3}' | cut -d- -f1 || true)"
  if [[ -n "${IM_VERSION_INSTALLED:-}" ]]; then
    echo "==> Found ImageMagick version: $IM_VERSION_INSTALLED (magick: $(command -v magick))"
    if version_ge "$IM_VERSION_INSTALLED" "$IM_MIN_VERSION"; then
      echo "==> ImageMagick >= $IM_MIN_VERSION detected; skipping source build"
      need_im_build=false
    else
      echo "==> ImageMagick < $IM_MIN_VERSION; will build from source"
    fi
  else
    echo "==> Could not parse ImageMagick version; will build from source"
  fi
else
  echo "==> ImageMagick not found; will build from source"
fi

if [[ "$need_im_build" == "true" ]]; then
  IM_VERSION="$(get_latest_imagemagick_tag || true)"
  if [[ -z "${IM_VERSION:-}" ]]; then
    echo "ERROR: Could not determine latest ImageMagick release tag from GitHub."
    echo "Tip: set GITHUB_TOKEN to avoid API rate limits."
    exit 1
  fi

  echo "==> Building ImageMagick ${IM_VERSION} from GitHub source into ${PREFIX}"
  mkdir -p "$HOME/.cache/imagemagick-src"
  cd "$HOME/.cache/imagemagick-src"

  rm -rf ImageMagick-* 2>/dev/null || true

  download_imagemagick_src "$IM_VERSION"

  if [[ -d "ImageMagick-${IM_VERSION}" ]]; then
    cd "ImageMagick-${IM_VERSION}"
  else
    cd "$(find . -maxdepth 1 -type d -name 'ImageMagick-*' | head -n1)"
  fi

  ./configure \
    --prefix="$PREFIX" \
    --disable-static \
    --with-modules \
    --with-quantum-depth=16 \
    --with-magick-plus-plus=yes

  make -j"$(nproc)"
  make install

  # Make libs + binaries visible in places ComfyUI/node installers actually check
  ensure_imagemagick_system_visibility "$PREFIX"

  echo "==> Verifying ImageMagick install ($PREFIX/bin/magick)"
  "$PREFIX/bin/magick" -version
else
  echo "==> Using existing ImageMagick installation"
  magick -version || true

  # Even if ImageMagick exists, ensure visibility for node installers/services.
  ensure_imagemagick_system_visibility "$PREFIX"
fi

# Optional but convenient for the ImageMagick ComfyUI nodes that rely on 'wand'
ensure_wand_available

echo "==> Done."
echo "Next:"
echo "  source ~/.zshrc"
echo "  ./scripts/install_custom_nodes.sh /workspace/vast-private/custom_nodes.txt"
echo "  ./scripts/download_models.sh /workspace/vast-private/models"