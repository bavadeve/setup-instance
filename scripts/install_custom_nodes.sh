#!/usr/bin/env bash
set -euo pipefail

# Install/update ComfyUI custom nodes from a list file.
#
# List format (one per line):
#   https://github.com/user/repo.git
#   https://github.com/user/repo.git @ <branch|tag|commit>
#
# Notes:
# - If no "@ ref" is provided, the repo's default branch is used (recommended).
# - If "@ ref" is provided, we fetch and checkout that ref.
# - Comments starting with "#" and blank lines are ignored.
#
# Usage:
#   ./scripts/install_custom_nodes.sh /path/to/custom_nodes.txt
#
# Env overrides:
#   COMFYUI_DIR=/workspace/ComfyUI
#   COMFY_CUSTOM_NODES_DIR=/workspace/ComfyUI/custom_nodes

COMFYUI_DIR="${COMFYUI_DIR:-/workspace/ComfyUI}"
NODES_DIR="${COMFY_CUSTOM_NODES_DIR:-$COMFYUI_DIR/custom_nodes}"

LIST_FILE="${1:-}"

if [[ -z "$LIST_FILE" ]]; then
  echo "ERROR: Provide a list file path."
  echo "Usage: $0 /path/to/custom_nodes.txt"
  exit 1
fi

if [[ ! -f "$LIST_FILE" ]]; then
  echo "ERROR: List file not found: $LIST_FILE"
  exit 1
fi

if ! command -v git >/dev/null 2>&1; then
  echo "ERROR: git not found"
  exit 1
fi

mkdir -p "$NODES_DIR"
echo "==> Custom nodes dir: $NODES_DIR"
echo "==> List file:        $LIST_FILE"

trim() {
  # trims leading/trailing whitespace
  local s="$1"
  # shellcheck disable=SC2001
  s="$(echo "$s" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  echo "$s"
}

repo_name_from_url() {
  local url="$1"
  local name
  name="$(basename "$url")"
  name="${name%.git}"
  echo "$name"
}

checkout_ref_if_needed() {
  local target="$1"
  local ref="$2"

  [[ -z "$ref" ]] && return 0

  echo "==> Checkout @ $ref"

  # Ensure we have enough refs to checkout branches/tags/commits.
  # (If cloned with depth, unshallow first.)
  if git -C "$target" rev-parse --is-shallow-repository >/dev/null 2>&1; then
    if [[ "$(git -C "$target" rev-parse --is-shallow-repository)" == "true" ]]; then
      git -C "$target" fetch --unshallow || true
    fi
  fi

  git -C "$target" fetch --all --tags --prune

  # Try in a robust order:
  # 1) direct ref (branch name, tag, commit)
  # 2) origin/<ref> for remote branch names
  if git -C "$target" checkout -q "$ref" 2>/dev/null; then
    return 0
  fi

  if git -C "$target" checkout -q "origin/$ref" 2>/dev/null; then
    return 0
  fi

  echo "ERROR: Could not checkout ref '$ref' in $target"
  echo "Tip: use a tag or commit hash, or omit '@ ...' to use the repo default branch."
  return 1
}

maybe_install_requirements() {
  local target="$1"

  # Optional: install python deps per node if requirements.txt exists.
  # Comment out this block if you prefer manual control.
  if [[ -f "$target/requirements.txt" ]]; then
    echo "==> Installing python deps: $(basename "$target")"
    python3 -m pip install -r "$target/requirements.txt"
  fi
}

install_one_line() {
  local line="$1"

  # Strip comments
  line="${line%%#*}"
  line="$(trim "$line")"
  [[ -z "$line" ]] && return 0

  local url ref
  if [[ "$line" == *"@"* ]]; then
    url="$(trim "$(echo "$line" | awk -F'@' '{print $1}')")"
    ref="$(trim "$(echo "$line" | awk -F'@' '{print $2}')")"
  else
    url="$line"
    ref=""
  fi

  if [[ -z "$url" ]]; then
    echo "ERROR: Bad line: '$line'"
    return 1
  fi

  local repo_name target
  repo_name="$(repo_name_from_url "$url")"
  target="$NODES_DIR/$repo_name"

  if [[ ! -d "$target/.git" ]]; then
    echo "==> Cloning $url -> $target"
    git clone "$url" "$target"
  else
    echo "==> Updating $repo_name"
    git -C "$target" fetch --all --tags --prune
    # If you want auto-update to latest on the current branch:
    # git -C "$target" pull --ff-only || true
  fi

  checkout_ref_if_needed "$target" "$ref"
  maybe_install_requirements "$target"
}

while IFS= read -r line || [[ -n "$line" ]]; do
  install_one_line "$line"
done < "$LIST_FILE"

echo "==> Done installing custom nodes."
