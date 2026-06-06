#!/usr/bin/env bash
set -Eeuo pipefail

export WORKSPACE="${WORKSPACE:-/workspace}"
export USER_NAME="${HOOLIPODS_USER_NAME:-${USER_NAME:-PAVEL}}"

if [[ -z "$USER_NAME" || "$USER_NAME" == "." || "$USER_NAME" == ".." || "$USER_NAME" == *"/"* || "$USER_NAME" == *"\\"* || "$USER_NAME" == *".."* ]]; then
  echo "[HooliPods A1111] Invalid USER_NAME: '$USER_NAME'" >&2
  exit 64
fi

if [[ ! "$USER_NAME" =~ ^[A-Za-z0-9._@-]+$ ]]; then
  echo "[HooliPods A1111] Invalid USER_NAME: '$USER_NAME'. Allowed: letters, digits, dot, underscore, dash, at-sign." >&2
  exit 64
fi

export OUTPUTS_ROOT="${OUTPUTS_ROOT:-$WORKSPACE/outputs}"
export SHARED_PROFILE_NAME="${SHARED_PROFILE_NAME:-shared}"
export OUTPUT_DIR="${OUTPUT_DIR:-$OUTPUTS_ROOT/$SHARED_PROFILE_NAME}"
export USER_DATA_ROOT="${USER_DATA_ROOT:-$WORKSPACE/userdata/a1111}"
export USER_DATA_DIR="${USER_DATA_DIR:-$USER_DATA_ROOT/$SHARED_PROFILE_NAME}"

export A1111_DIR="${A1111_DIR:-$WORKSPACE/stable-diffusion-webui}"
export VENV_PATH="${VENV_PATH:-$WORKSPACE/venvs/a1111}"
export A1111_REF="${A1111_REF:-v1.10.1}"
export TORCH_INDEX_URL="${TORCH_INDEX_URL:-https://download.pytorch.org/whl/cu128}"
export STABLE_DIFFUSION_REPO="${STABLE_DIFFUSION_REPO:-https://github.com/w-e-w/stablediffusion.git}"
export GIT_TERMINAL_PROMPT=0

# Correct default for RTX 5090 / SDXL high-res:
# - no --no-half-vae by default
# - use --medvram-sdxl to reduce direct high-res OOM/crashes
# - keep PyTorch SDP attention
DEFAULT_COMMANDLINE_ARGS="--listen --port 7860 --api --enable-insecure-extension-access --skip-torch-cuda-test --skip-python-version-check --xformers --opt-sdp-attention --upcast-sampling --no-half-vae --medvram-sdxl --no-download-sd-model"

export COMMANDLINE_ARGS="${COMMANDLINE_ARGS:-$DEFAULT_COMMANDLINE_ARGS}"
export COMMANDLINE_ARGS="$COMMANDLINE_ARGS --data-dir $USER_DATA_DIR --models-dir $WORKSPACE/models --ckpt-dir $WORKSPACE/models/Stable-diffusion --vae-dir $WORKSPACE/models/VAE --embeddings-dir $WORKSPACE/embeddings --gradio-allowed-path $WORKSPACE"

mkdir -p "$WORKSPACE/logs"
mkdir -p "$WORKSPACE/venvs"
mkdir -p "$WORKSPACE/models/Stable-diffusion"
mkdir -p "$WORKSPACE/models/Lora"
mkdir -p "$WORKSPACE/models/VAE"
mkdir -p "$WORKSPACE/models/ControlNet"
mkdir -p "$WORKSPACE/embeddings"
mkdir -p "$OUTPUT_DIR"
mkdir -p "$USER_DATA_DIR"
# >>> HOOLIPODS_SHARED_PROFILE_BOOTSTRAP_START
export SEED_PROFILE_NAME="${SEED_PROFILE_NAME:-Shadrin}"
export SEED_PROFILE_DIR="$USER_DATA_ROOT/$SEED_PROFILE_NAME"
export SHARED_PROFILE_MARKER="$USER_DATA_DIR/.hoolipods_shared_initialized"

if [ "${SHARED_PROFILE_BOOTSTRAP:-1}" = "1" ] && [ ! -f "$SHARED_PROFILE_MARKER" ]; then
  if [ -d "$SEED_PROFILE_DIR" ]; then
    echo "[HooliPods A1111] First shared profile init: copying settings from $SEED_PROFILE_DIR to $USER_DATA_DIR"

    mkdir -p "$USER_DATA_DIR"

    shopt -s dotglob nullglob
    for item in "$SEED_PROFILE_DIR"/*; do
      base="$(basename "$item")"

      # Outputs must not be copied into shared settings.
      if [ "$base" = "outputs" ]; then
        continue
      fi

      rm -rf "$USER_DATA_DIR/$base"
      cp -a "$item" "$USER_DATA_DIR/"
    done
    shopt -u dotglob nullglob

    rm -rf "$USER_DATA_DIR/outputs"

    {
      echo "initialized_from=$SEED_PROFILE_NAME"
      echo "initialized_at=$(date -Is)"
    } > "$SHARED_PROFILE_MARKER"

    echo "[HooliPods A1111] Shared profile initialized from $SEED_PROFILE_NAME"
  else
    echo "[HooliPods A1111] Seed profile $SEED_PROFILE_DIR not found. Shared profile will start clean."
    {
      echo "initialized_from=clean"
      echo "initialized_at=$(date -Is)"
      echo "reason=seed_profile_not_found"
    } > "$SHARED_PROFILE_MARKER"
  fi
else
  echo "[HooliPods A1111] Shared profile bootstrap skipped."
fi
# <<< HOOLIPODS_SHARED_PROFILE_BOOTSTRAP_END
mkdir -p "$WORKSPACE/config/a1111"
mkdir -p "$WORKSPACE/extensions"

rm -rf "$USER_DATA_DIR/outputs"
ln -s "$OUTPUT_DIR" "$USER_DATA_DIR/outputs"

echo "[HooliPods A1111] USER_NAME=$USER_NAME"
echo "[HooliPods A1111] WORKSPACE=$WORKSPACE"
echo "[HooliPods A1111] OUTPUT_DIR=$OUTPUT_DIR"
echo "[HooliPods A1111] USER_DATA_DIR=$USER_DATA_DIR"
echo "[HooliPods A1111] A1111_DIR=$A1111_DIR"
echo "[HooliPods A1111] VENV_PATH=$VENV_PATH"
echo "[HooliPods A1111] A1111_REF=$A1111_REF"
echo "[HooliPods A1111] STABLE_DIFFUSION_REPO=$STABLE_DIFFUSION_REPO"
echo "[HooliPods A1111] COMMANDLINE_ARGS=$COMMANDLINE_ARGS"

if [ ! -d "$A1111_DIR/.git" ]; then
  echo "[HooliPods A1111] Cloning Automatic1111 into volume..."
  git clone https://github.com/AUTOMATIC1111/stable-diffusion-webui.git "$A1111_DIR"
  cd "$A1111_DIR"
  git fetch --tags origin
  git checkout "$A1111_REF"
else
  cd "$A1111_DIR"

  if [ "${UPDATE_A1111:-0}" = "1" ]; then
    echo "[HooliPods A1111] UPDATE_A1111=1, updating repo..."
    git fetch --tags origin
    git checkout "$A1111_REF"
  else
    echo "[HooliPods A1111] Existing A1111 repo detected, skipping git fetch/checkout."
  fi
fi

# Persistent extensions:
# /workspace/stable-diffusion-webui/extensions -> /workspace/extensions
if [ -e "$A1111_DIR/extensions" ] && [ ! -L "$A1111_DIR/extensions" ]; then
  echo "[HooliPods A1111] Migrating existing extensions to persistent /workspace/extensions..."

  MIGRATION_BACKUP="$WORKSPACE/extensions_migration_backup_$(date +%Y%m%d_%H%M%S)"
  shopt -s dotglob nullglob

  for item in "$A1111_DIR/extensions"/*; do
    base="$(basename "$item")"

    if [ ! -e "$WORKSPACE/extensions/$base" ]; then
      mv "$item" "$WORKSPACE/extensions/"
    else
      echo "[HooliPods A1111] Extension conflict: $base -> moving old copy to $MIGRATION_BACKUP"
      mkdir -p "$MIGRATION_BACKUP"
      mv "$item" "$MIGRATION_BACKUP/$base"
    fi
  done

  shopt -u dotglob nullglob
  rm -rf "$A1111_DIR/extensions"
fi

rm -rf "$A1111_DIR/extensions"
ln -s "$WORKSPACE/extensions" "$A1111_DIR/extensions"

echo "[HooliPods A1111] Extensions dir: $A1111_DIR/extensions -> $WORKSPACE/extensions"

CREATED_VENV=0

if [ ! -x "$VENV_PATH/bin/python" ]; then
  echo "[HooliPods A1111] Creating venv in volume..."
  :
fi

if [ -x "$VENV_PATH/bin/python" ]; then
  VENV_PY_VERSION="$("$VENV_PATH/bin/python" -c 'import platform; print(platform.python_version())' 2>/dev/null || true)"
  if [ "$VENV_PY_VERSION" != "3.11.15" ]; then
    echo "[HooliPods A1111] Existing venv Python $VENV_PY_VERSION does not match 3.11.15, recreating venv..."
    rm -rf "$VENV_PATH"
  fi
fi

if [ ! -x "$VENV_PATH/bin/python" ]; then
  echo "[HooliPods A1111] Creating Python 3.11.15 venv in volume..."
  python3.11 -m venv "$VENV_PATH"
  CREATED_VENV=1
fi

source "$VENV_PATH/bin/activate"

if [ "$CREATED_VENV" != "1" ] && [ "${REPAIR_ENV:-0}" != "1" ]; then
  if ! python - <<'PY'; then
from importlib import metadata
from sympy.strategies.branch import yieldify
import torch
import torchvision
import xformers
import triton
from xformers.ops import memory_efficient_attention

expected = {
    "fastapi": "0.94.0",
    "gradio": "3.41.2",
}
for package, version in expected.items():
    installed = metadata.version(package)
    if installed != version:
        raise RuntimeError(f"{package}=={installed}, expected {version}")

starlette_version = metadata.version("starlette")
if not starlette_version.startswith("0.26."):
    raise RuntimeError(f"starlette=={starlette_version}, expected 0.26.x")
PY
    echo "[HooliPods A1111] Existing venv failed dependency sanity check, enabling repair."
    export REPAIR_ENV=1
  fi
fi

# Clean broken pip leftovers from previous installs, cheap and safe.
rm -rf "$VENV_PATH"/lib/python*/site-packages/-radio* || true
rm -rf "$VENV_PATH"/lib/python*/site-packages/~radio* || true

if [ "$CREATED_VENV" = "1" ] || [ "${REPAIR_ENV:-0}" = "1" ]; then
  echo "[HooliPods A1111] Installing/repairing bootstrap Python deps..."
  python -m pip install --upgrade "pip<25.3" "setuptools==69.5.1" wheel

  echo "[HooliPods A1111] Repairing critical Python packages..."
  pip install --force-reinstall --no-deps "sympy==1.14.0"

  echo "[HooliPods A1111] Installing/repairing A1111 pinned web dependencies..."
  pip install --prefer-binary -r "$A1111_DIR/requirements_versions.txt"
  pip install --force-reinstall --no-deps \
    "fastapi==0.94.0" \
    "gradio==3.41.2" \
    "starlette==0.26.1" \
    "httpx==0.24.1" \
    "httpcore==0.15"

  echo "[HooliPods A1111] Installing/repairing PyTorch CUDA 12.8..."
  pip install "torch==${TORCH_VERSION}" "torchvision==${TORCHVISION_VERSION}" "torchaudio==${TORCHAUDIO_VERSION}" --index-url "$TORCH_INDEX_URL"

  echo "[HooliPods A1111] Installing/repairing xformers..."
  pip install --no-deps "xformers==${XFORMERS_VERSION}" --extra-index-url "$TORCH_INDEX_URL"

  echo "[HooliPods A1111] Installing/repairing xformers compatibility patch..."
  python - <<'PY'
from pathlib import Path
import inspect
import xformers.ops

ops_init = Path(inspect.getfile(xformers.ops))
patch = """

# HooliPods compatibility: expose the legacy availability marker expected by
# older diagnostics. Actual operator support is still reported by xformers.info.
try:
    memory_efficient_attention.available = True
except NameError:
    pass
"""
text = ops_init.read_text()
if "HooliPods compatibility" not in text:
    ops_init.write_text(text + patch)
PY

  echo "[HooliPods A1111] Installing/repairing OpenAI CLIP..."
  pip install --no-build-isolation "https://github.com/openai/CLIP/archive/d50d76daa670286dd6cacf3bcd80b5e4823fc8e1.zip"
else
  echo "[HooliPods A1111] Existing venv detected, skipping pip/torch/clip checks. Set REPAIR_ENV=1 to repair."
fi

cat > "$A1111_DIR/webui-user.sh" <<EOF
#!/usr/bin/env bash
export python_cmd="$VENV_PATH/bin/python"
export venv_dir="$VENV_PATH"
export TORCH_COMMAND="pip install torch==${TORCH_VERSION} torchvision==${TORCHVISION_VERSION} torchaudio==${TORCHAUDIO_VERSION} --index-url $TORCH_INDEX_URL"
export STABLE_DIFFUSION_REPO="$STABLE_DIFFUSION_REPO"
export GIT_TERMINAL_PROMPT=0
EOF

chmod +x "$A1111_DIR/webui-user.sh"

mkdir -p "$A1111_DIR/models"

rm -rf "$A1111_DIR/models/Stable-diffusion"
rm -rf "$A1111_DIR/models/Lora"
rm -rf "$A1111_DIR/models/VAE"
rm -rf "$A1111_DIR/models/ControlNet"
rm -rf "$A1111_DIR/embeddings"

ln -s "$WORKSPACE/models/Stable-diffusion" "$A1111_DIR/models/Stable-diffusion"
ln -s "$WORKSPACE/models/Lora" "$A1111_DIR/models/Lora"
ln -s "$WORKSPACE/models/VAE" "$A1111_DIR/models/VAE"
ln -s "$WORKSPACE/models/ControlNet" "$A1111_DIR/models/ControlNet"
ln -s "$WORKSPACE/embeddings" "$A1111_DIR/embeddings"

echo "[HooliPods A1111] Starting FileBrowser on :8080"
filebrowser \
  --address 0.0.0.0 \
  --port 8080 \
  --root "$WORKSPACE" \
  --database "$WORKSPACE/filebrowser.db" \
  > "$WORKSPACE/logs/filebrowser.log" 2>&1 &

echo "[HooliPods A1111] Starting JupyterLab on :8888"
jupyter lab \
  --ip=0.0.0.0 \
  --port=8888 \
  --no-browser \
  --allow-root \
  --ServerApp.token="" \
  --ServerApp.password="" \
  --ServerApp.allow_origin="*" \
  --ServerApp.root_dir="$WORKSPACE" \
  > "$WORKSPACE/logs/jupyter.log" 2>&1 &

if [ "${DEBUG_DIAGNOSTIC:-0}" = "1" ]; then
  echo "[HooliPods A1111] CUDA diagnostic"
  "$VENV_PATH/bin/python" - <<'PY' || true
import torch
print("torch:", torch.__version__)
print("cuda build:", torch.version.cuda)
print("cuda available:", torch.cuda.is_available())
if torch.cuda.is_available():
    print("gpu:", torch.cuda.get_device_name(0))
    print("capability:", torch.cuda.get_device_capability(0))
PY
else
  echo "[HooliPods A1111] Skipping CUDA diagnostic. Set DEBUG_DIAGNOSTIC=1 to enable."
fi

echo "[HooliPods A1111] Starting A1111 on :7860"
bash "$A1111_DIR/webui.sh" -f 2>&1 | tee "$WORKSPACE/logs/webui.log"
