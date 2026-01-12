# ============================================================
# Model download helpers (curl-only, simple & debuggable)
# ============================================================

# Internal fetch:
# - If output is a directory: use -J -O (server decides filename)
# - If output is a file path: force filename with -o
function _fetch_url() {
  local url="$1"
  local out="$2"
  shift 2

  local headers=()
  for h in "$@"; do
    headers+=("-H" "$h")
  done

  if [[ -d "$out" || "$out" == */ ]]; then
    mkdir -p "$out"
    (
      cd "$out" || exit 1
      curl -fL -J -O "${headers[@]}" "$url"
    )
  else
    mkdir -p "$(dirname "$out")"
    curl -fL "${headers[@]}" "$url" -o "$out"
  fi
}

# -----------------------------
# Source-specific downloaders
# -----------------------------

function civitai_download() {
  local url="$1"
  local outdir="${2:-.}"

  if [[ -z "${CIVITAI_API_KEY:-}" ]]; then
    echo "ERROR: CIVITAI_API_KEY is not set"
    return 1
  fi

  echo "==> Civitai: $url"
  _fetch_url "$url" "$outdir" \
    "Authorization: Bearer ${CIVITAI_API_KEY}" \
    "User-Agent: Mozilla/5.0"
}

function hf_download() {
  local url="$1"
  local outdir="${2:-.}"

  local headers=("User-Agent: Mozilla/5.0")
  [[ -n "${HF_TOKEN:-}" ]] && headers+=("Authorization: Bearer ${HF_TOKEN}")

  echo "==> HuggingFace: $url"
  _fetch_url "$url" "$outdir" "${headers[@]}"
}

# -----------------------------
# Dispatcher
# -----------------------------

function model_download() {
  local url="$1"
  local outdir="${2:-.}"

  if [[ "$url" == *"civitai.com/api/download/models/"* ]]; then
    civitai_download "$url" "$outdir"
  elif [[ "$url" == *"huggingface.co/"*"/resolve/"* ]]; then
    hf_download "$url" "$outdir"
  else
    echo "==> Direct: $url"
    _fetch_url "$url" "$outdir" "User-Agent: Mozilla/5.0"
  fi
}

# -----------------------------
# Batch downloader
# -----------------------------
# Supports:
#   - comments (#)
#   - blank lines
#   - URL
#   - URL -> filename
# Continues on failure, prints summary at end.
function download_list() {
  local listfile="$1"
  local outdir="$2"

  if [[ -z "$listfile" || -z "$outdir" ]]; then
    echo "Usage: download_list <listfile.txt> <outdir>"
    return 2
  fi

  if [[ ! -f "$listfile" ]]; then
    echo "ERROR: list file not found: $listfile"
    return 2
  fi

  mkdir -p "$outdir"

  local total=0 ok=0 fail=0
  local failed_items=()

  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    line="$(echo "$line" | xargs)"
    [[ -z "$line" ]] && continue

    total=$((total + 1))

    if [[ "$line" == *"->"* ]]; then
      local url="$(echo "$line" | awk -F'->' '{print $1}' | xargs)"
      local fname="$(echo "$line" | awk -F'->' '{print $2}' | xargs)"

      echo "==> [$total] Explicit: $url -> $outdir/$fname"

      if _fetch_url "$url" "$outdir/$fname"; then
        ok=$((ok + 1))
      else
        echo "!! FAILED: $url"
        fail=$((fail + 1))
        failed_items+=("$url -> $fname")
      fi
    else
      echo "==> [$total] $line"
      if model_download "$line" "$outdir"; then
        ok=$((ok + 1))
      else
        echo "!! FAILED: $line"
        fail=$((fail + 1))
        failed_items+=("$line")
      fi
    fi

  done < "$listfile"

  echo "==> Done: $ok ok, $fail failed (total $((ok + fail)))"

  if (( fail > 0 )); then
    echo "==> Failed items:"
    for item in "${failed_items[@]}"; do
      echo "  - $item"
    done
    return 1
  fi

  return 0
}
