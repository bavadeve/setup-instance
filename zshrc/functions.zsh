# Universal model downloader supporting:
# - Civitai API download URLs (requires CIVITAI_API_KEY)
# - HuggingFace "resolve/main/..." URLs (optional HF_TOKEN)
# - Direct URLs
#
# Uses aria2c if available (faster), otherwise curl.

function _fetch_url() {
  local url="$1"
  local out="$2"
  shift 2

  mkdir -p "$(dirname "$out")"

  if command -v aria2c >/dev/null 2>&1; then
    local aria_headers=()
    for h in "$@"; do
      aria_headers+=("--header=$h")
    done
    aria2c -c -x 8 -s 8 --allow-overwrite=true \
      "${aria_headers[@]}" \
      -o "$(basename "$out")" -d "$(dirname "$out")" \
      "$url"
  else
    local curl_headers=()
    for h in "$@"; do
      curl_headers+=("-H" "$h")
    done
    curl -fL -C - "${curl_headers[@]}" "$url" -o "$out"
  fi
}

function _filename_from_url() {
  local url="$1"
  local name="${url##*/}"
  name="${name%%\?*}"
  if [[ -z "$name" || "$name" == "download" ]]; then
    name="model.bin"
  fi
  echo "$name"
}

function civitai_download() {
  local url="$1"
  local outdir="${2:-.}"
  local fname="$(_filename_from_url "$url")"

  if [[ -z "${CIVITAI_API_KEY:-}" ]]; then
    echo "ERROR: CIVITAI_API_KEY is not set"
    return 1
  fi

  local header="Authorization: Bearer ${CIVITAI_API_KEY}"
  echo "==> Civitai: $url"
  _fetch_url "$url" "$outdir/$fname" "$header"
}

function hf_download() {
  local url="$1"
  local outdir="${2:-.}"
  local fname="$(_filename_from_url "$url")"

  local headers=()
  if [[ -n "${HF_TOKEN:-}" ]]; then
    headers+=("Authorization: Bearer ${HF_TOKEN}")
  fi

  echo "==> HuggingFace: $url"
  if (( ${#headers[@]} > 0 )); then
    _fetch_url "$url" "$outdir/$fname" "${headers[@]}"
  else
    _fetch_url "$url" "$outdir/$fname"
  fi
}

function model_download() {
  local url="$1"
  local outdir="${2:-.}"

  if [[ "$url" == *"civitai.com/api/download/models/"* ]]; then
    civitai_download "$url" "$outdir"
  elif [[ "$url" == *"huggingface.co/"*"/resolve/"* ]]; then
    hf_download "$url" "$outdir"
  else
    local fname="$(_filename_from_url "$url")"
    echo "==> Direct: $url"
    _fetch_url "$url" "$outdir/$fname"
  fi
}

# Batch download list: supports comments (#) and blank lines.
# Also supports "URL -> filename" syntax if you want it.
function download_list() {
  local listfile="$1"
  local outdir="$2"
  mkdir -p "$outdir"

  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"                   # strip comments
    line="$(echo "$line" | xargs)"       # trim
    [[ -z "$line" ]] && continue

    # Optional: "URL -> filename"
    if [[ "$line" == *"->"* ]]; then
      local url="$(echo "$line" | awk -F'->' '{print $1}' | xargs)"
      local fname="$(echo "$line" | awk -F'->' '{print $2}' | xargs)"
      [[ -z "$url" || -z "$fname" ]] && { echo "ERROR: Bad line: $line"; return 1; }
      echo "==> Explicit: $url -> $outdir/$fname"
      _fetch_url "$url" "$outdir/$fname"
    else
      model_download "$line" "$outdir" || return 1
    fi
  done < "$listfile"
}
