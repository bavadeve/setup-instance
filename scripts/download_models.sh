#!/usr/bin/env bash
set -euo pipefail

# Download models listed in *.txt files into /workspace/ComfyUI/models/<listname>/
# Only downloads if the target file does NOT already exist.
#
# List format (one per line):
#   URL
#   URL -> filename
# Comments (#) and blank lines are ignored.
#
# Detection logic:
# - If "URL -> filename" is used, we check for that filename in the target dir.
# - Otherwise we try to infer a stable filename from the URL path (best effort).
#   If we cannot infer a filename, we fall back to downloading into a temp dir and
#   skipping if a file with the same server-provided name already exists.

MODELS_DIR="${COMFY_MODELS_DIR:-/workspace/ComfyUI/models}"
LIST_DIR="${1:-}"

if [[ -z "$LIST_DIR" ]]; then
  echo "Usage: $0 <list_dir_containing_txt_files>"
  exit 2
fi

if [[ ! -d "$LIST_DIR" ]]; then
  echo "ERROR: list dir not found: $LIST_DIR"
  exit 2
fi

# Load zsh functions (model_download expects zsh). We'll call zsh explicitly.
FUNCS_PATH="${FUNCS_PATH:-$HOME/.config/vast-bootstrap/functions.zsh}"
if [[ ! -f "$FUNCS_PATH" ]]; then
  echo "ERROR: functions.zsh not found at: $FUNCS_PATH"
  exit 2
fi

mkdir -p "$MODELS_DIR"

echo "==> Models dir: $MODELS_DIR"
echo "==> List dir:   $LIST_DIR"

shopt -s nullglob
lists=( "$LIST_DIR"/*.txt )
if (( ${#lists[@]} == 0 )); then
  echo "ERROR: No .txt list files found in: $LIST_DIR"
  exit 2
fi

infer_name_from_url() {
  # Best-effort inference from URL path:
  # - take last path segment
  # - strip query string
  local url="$1"
  local name="${url##*/}"
  name="${name%%\?*}"
  # If it looks empty or too generic, return empty (caller will use fallback)
  if [[ -z "$name" || "$name" == "download" || "$name" == "models" ]]; then
    echo ""
  else
    echo "$name"
  fi
}

run_zsh_model_download() {
  local url="$1"
  local outdir="$2"
  # Run in zsh so we can source your functions.zsh
  zsh -lc "source '$FUNCS_PATH'; model_download '$url' '$outdir'"
}

for listfile in "${lists[@]}"; do
  base="$(basename "$listfile")"
  subdir="${base%.txt}"
  target_dir="$MODELS_DIR/$subdir"
  mkdir -p "$target_dir"

  echo "==> Processing $base -> $target_dir"

  total=0; skipped=0; downloaded=0; failed=0

  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    line="$(echo "$line" | xargs)"
    [[ -z "$line" ]] && continue

    total=$((total + 1))

    url=""
    fname=""

    if [[ "$line" == *"->"* ]]; then
      url="$(echo "$line" | awk -F'->' '{print $1}' | xargs)"
      fname="$(echo "$line" | awk -F'->' '{print $2}' | xargs)"
      if [[ -z "$url" || -z "$fname" ]]; then
        echo "!! BAD LINE: $line"
        failed=$((failed + 1))
        continue
      fi

      if [[ -f "$target_dir/$fname" ]]; then
        echo "==> SKIP (exists): $fname"
        skipped=$((skipped + 1))
        continue
      fi

      echo "==> DOWNLOAD: $url -> $fname"
      # Use zsh model_download but force name by using URL->filename syntax via curl -o:
      # easiest: call zsh and use _fetch_url directly isn't exposed; so we do a tiny inline curl:
      # However we keep auth handling by calling model_download into a temp dir then rename.
      tmpdir="$(mktemp -d)"
      if run_zsh_model_download "$url" "$tmpdir"; then
        # take the only file downloaded (best effort)
        dlfile="$(ls -1 "$tmpdir" | head -n 1 || true)"
        if [[ -z "$dlfile" ]]; then
          echo "!! FAILED: no file produced for $url"
          failed=$((failed + 1))
        else
          mv -f "$tmpdir/$dlfile" "$target_dir/$fname"
          echo "==> Saved as: $target_dir/$fname"
          downloaded=$((downloaded + 1))
        fi
      else
        echo "!! FAILED: $url"
        failed=$((failed + 1))
      fi
      rm -rf "$tmpdir"
      continue
    fi

    url="$line"
    fname="$(infer_name_from_url "$url")"

    if [[ -n "$fname" && -f "$target_dir/$fname" ]]; then
      echo "==> SKIP (exists): $fname"
      skipped=$((skipped + 1))
      continue
    fi

    # Fallback: if we can't infer a filename, try a temp download and then move if new.
    if [[ -z "$fname" ]]; then
      echo "==> DOWNLOAD (unknown name): $url"
      tmpdir="$(mktemp -d)"
      if run_zsh_model_download "$url" "$tmpdir"; then
        dlfile="$(ls -1 "$tmpdir" | head -n 1 || true)"
        if [[ -z "$dlfile" ]]; then
          echo "!! FAILED: no file produced for $url"
          failed=$((failed + 1))
        else
          if [[ -f "$target_dir/$dlfile" ]]; then
            echo "==> SKIP (exists after name known): $dlfile"
            skipped=$((skipped + 1))
          else
            mv -f "$tmpdir/$dlfile" "$target_dir/$dlfile"
            echo "==> Saved: $target_dir/$dlfile"
            downloaded=$((downloaded + 1))
          fi
        fi
      else
        echo "!! FAILED: $url"
        failed=$((failed + 1))
      fi
      rm -rf "$tmpdir"
      continue
    fi

    echo "==> DOWNLOAD: $url"
    if run_zsh_model_download "$url" "$target_dir"; then
      # Note: server decides filename; we assume it matches inferred fname most of the time
      downloaded=$((downloaded + 1))
    else
      echo "!! FAILED: $url"
      failed=$((failed + 1))
    fi

  done < "$listfile"

  echo "==> Summary for $base: total=$total, downloaded=$downloaded, skipped=$skipped, failed=$failed"
done

echo "==> All lists processed."
