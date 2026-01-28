#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Where ComfyUI expects models on Vast:
MODELS_DIR="${COMFY_MODELS_DIR:-/workspace/ComfyUI/models}"

# Directory containing model type folders
LIST_DIR="${1:-$REPO_ROOT/models}"

echo "==> Models dir: $MODELS_DIR"
echo "==> List dir:   $LIST_DIR"

# Check if list directory exists
if [[ ! -d "$LIST_DIR" ]]; then
  echo "ERROR: Directory not found: $LIST_DIR"
  exit 1
fi

# Find all subdirectories (model types like illustrious, flux, etc.)
mapfile -t model_types < <(find "$LIST_DIR" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort)

if (( ${#model_types[@]} == 0 )); then
  echo "ERROR: No model type folders found in: $LIST_DIR"
  exit 1
fi

# Display available options
echo ""
echo "Available model types:"
echo "----------------------"
for i in "${!model_types[@]}"; do
  # Count .txt files in each folder
  txt_count=$(find "$LIST_DIR/${model_types[$i]}" -maxdepth 1 -name "*.txt" | wc -l)
  echo "  $((i + 1))) ${model_types[$i]} ($txt_count list files)"
done
echo ""
echo "  0) All"
echo ""

# Get user input
read -rp "Select model types to download (comma-separated, e.g., 1,3 or 0 for all): " selection

# Parse selection
declare -a selected_types

if [[ "$selection" == "0" ]]; then
  selected_types=("${model_types[@]}")
else
  IFS=',' read -ra indices <<< "$selection"
  for idx in "${indices[@]}"; do
    # Trim whitespace
    idx=$(echo "$idx" | xargs)
    
    # Validate input
    if ! [[ "$idx" =~ ^[0-9]+$ ]]; then
      echo "ERROR: Invalid input '$idx' - must be a number"
      exit 1
    fi
    
    # Convert to 0-based index
    array_idx=$((idx - 1))
    
    if (( array_idx < 0 || array_idx >= ${#model_types[@]} )); then
      echo "ERROR: Selection '$idx' out of range"
      exit 1
    fi
    
    selected_types+=("${model_types[$array_idx]}")
  done
fi

if (( ${#selected_types[@]} == 0 )); then
  echo "ERROR: No valid selections made"
  exit 1
fi

echo ""
echo "==> Selected: ${selected_types[*]}"
echo ""

mkdir -p "$MODELS_DIR"

# Load helper functions (download_list, etc.)
# shellcheck disable=SC1090
source "$HOME/.config/vast-bootstrap/functions.zsh"

shopt -s nullglob

# Process each selected model type
for model_type in "${selected_types[@]}"; do
  type_dir="$LIST_DIR/$model_type"
  echo "==> Processing: $model_type"
  
  lists=("$type_dir"/*.txt)
  
  if (( ${#lists[@]} == 0 )); then
    echo "    WARNING: No .txt files found in $type_dir, skipping..."
    continue
  fi
  
  for listfile in "${lists[@]}"; do
    base="$(basename "$listfile")"
    subdir="${base%.txt}"  # e.g. loras.txt -> loras
    
    # Include model type as subfolder: models/loras/illustrious/
    target="$MODELS_DIR/$subdir/$model_type"
    echo "    $(basename "$listfile") → $target"
    
    if ! download_list "$listfile" "$target"; then
      echo "    WARNING: Failed to download some models from $base, continuing..."
    fi
  done
done

echo ""
echo "==> All model downloads completed."