#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Where ComfyUI expects models on Vast:
MODELS_DIR="${COMFY_MODELS_DIR:-/workspace/ComfyUI/models}"

# Directory containing *.txt lists
LIST_DIR="${1:-$REPO_ROOT/models}"

echo "==> Models dir: $MODELS_DIR"
echo "==> List dir:   $LIST_DIR"

mkdir -p "$MODELS_DIR"

# Load helper functions (download_list, etc.)
# shellcheck disable=SC1090
source "$HOME/.config/vast-bootstrap/functions.zsh"

shopt -s nullglob

lists=( "$LIST_DIR"/*.txt )

if (( ${#lists[@]} == 0 )); then
  echo "ERROR: No .txt list files found in: $LIST_DIR"
  exit 1
fi

for listfile in "${lists[@]}"; do
  base="$(basename "$listfile")"
  subdir="${base%.txt}"  # e.g. text_encoders.txt -> text_encoders

  target="$MODELS_DIR/$subdir"
  echo "==> $(basename "$listfile") → $target"

  download_list "$listfile" "$target"
done

echo "==> All model downloads completed."
