export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="robbyrussell"
plugins=(git)

source $ZSH/oh-my-zsh.sh

# Put user-local binaries first (ImageMagick from source)
export PATH="$HOME/.local/bin:$PATH"

# ComfyUI defaults on Vast
export COMFYUI_DIR="/workspace/ComfyUI"
export COMFY_MODELS_DIR="/workspace/ComfyUI/models"
export COMFY_CUSTOM_NODES_DIR="/workspace/ComfyUI/custom_nodes"

# Load our helper functions
source "$HOME/.config/vast-bootstrap/functions.zsh"

# Optionally auto-load a private secrets file if you want (kept outside git):
if [[ -f /workspace/vast-private/secrets.env ]]; then
  source /workspace/vast-private/secrets.env
fi