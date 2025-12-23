#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

COMFYUI_DIR="${COMFYUI_DIR:-/workspace/ComfyUI}"
NODES_DIR="${COMFY_CUSTOM_NODES_DIR:-$COMFYUI_DIR/custom_nodes}"

LIST_FILE="${1:-$REPO_ROOT/custom_nodes.txt}"

mkdir -p "$NODES_DIR"

echo "==> Custom nodes dir: $NODES_DIR"
echo "==> List file:        $LIST_FILE"

if ! command -v git >/dev/null 2>&1; then
  echo "ERROR: git not found"
  exit 1
fi

install_one() {
  local line="$1"
  line="${line%%#*}"             # strip comments
  line="$(echo "$line" | xargs)" # trim
  [[ -z "$line" ]] && return 0

  # Parse "url @ ref" (ref optional)
  local url ref
  if [[ "$line" == *"@"* ]]; then
    url="$(echo "$line" | awk -F'@' '{print $1}' | xargs)"
    ref="$(echo "$line" | awk -F'@' '{print $2}' | xargs)"
  else
    url="$line"
    ref="main"
  fi

  local repo_name
  repo_name="$(basename "$url")"
  repo_name="${repo_name%.git}"

  local target="$NODES_DIR/$repo_name"

  if [[ ! -d "$target/.git" ]]; then
    echo "==> Cloning $url -> $target"
    git clone "$url" "$target"
  else
    echo "==> Updating $repo_name"
    git -C "$target" fetch --all --tags --prune
  fi

  echo "==> Checkout $repo_name @ $ref"
  if git -C "$target" rev-parse --verify -q "$ref" >/dev/null; then
    git -C "$target" checkout -q "$ref"
  else
    git -C "$target" checkout -q "$ref" 2>/dev/null || git -C "$target" checkout -q "origin/$ref"
  fi

  # Optional: install python deps per node if requirements.txt exists.
  # Comment these lines out if your template already handles deps or you prefer manual control.
  if [[ -f "$target/requirements.txt" ]]; then
    echo "==> Installing python deps for $repo_name"
    python3 -m pip install -r "$target/requirements.txt"
  fi
}

if [[ ! -f "$LIST_FILE" ]]; then
  echo "ERROR: List file not found: $LIST_FILE"
  exit 1
fi

while IFS= read -r line || [[ -n "$line" ]]; do
  install_one "$line"
done < "$LIST_FILE"

echo "==> Done installing custom nodes."
