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
export OUTPUT_DIR="$OUTPUTS_ROOT/$USER_NAME"

export A1111_DIR="${A1111_DIR:-$WORKSPACE/stable-diffusion-webui}"
export VENV_PATH="${VENV_PATH:-$WORKSPACE/venvs/a1111}"
export A1111_REF="${A1111_REF:-v1.10.1}"
export TORCH_INDEX_URL="${TORCH_INDEX_URL:-https://download.pytorch.org/whl/cu128}"
export STABLE_DIFFUSION_REPO="${STABLE_DIFFUSION_REPO:-https://github.com/w-e-w/stablediffusion.git}"
export GIT_TERMINAL_PROMPT=0

export COMMANDLINE_ARGS="${COMMANDLINE_ARGS:---listen --port 7860 --api --enable-insecure-extension-access --skip-torch-cuda-test --skip-python-version-check --opt-sdp-attention --no-half-vae --no-download-sd-model --gradio-allowed-path /workspace}"

mkdir -p "$WORKSPACE/logs"
mkdir -p "$WORKSPACE/venvs"
mkdir -p "$WORKSPACE/models/Stable-diffusion"
mkdir -p "$WORKSPACE/models/Lora"
mkdir -p "$WORKSPACE/models/VAE"
mkdir -p "$WORKSPACE/models/ControlNet"
mkdir -p "$WORKSPACE/embeddings"
mkdir -p "$OUTPUT_DIR"
mkdir -p "$WORKSPACE/config/a1111"

echo "[HooliPods A1111] USER_NAME=$USER_NAME"
echo "[HooliPods A1111] WORKSPACE=$WORKSPACE"
echo "[HooliPods A1111] OUTPUT_DIR=$OUTPUT_DIR"
echo "[HooliPods A1111] A1111_DIR=$A1111_DIR"
echo "[HooliPods A1111] VENV_PATH=$VENV_PATH"
echo "[HooliPods A1111] A1111_REF=$A1111_REF"
echo "[HooliPods A1111] STABLE_DIFFUSION_REPO=$STABLE_DIFFUSION_REPO"
echo "[HooliPods A1111] COMMANDLINE_ARGS=$COMMANDLINE_ARGS"

if [ ! -d "$A1111_DIR/.git" ]; then
  echo "[HooliPods A1111] Cloning Automatic1111 into volume..."
  git clone https://github.com/AUTOMATIC1111/stable-diffusion-webui.git "$A1111_DIR"
fi

cd "$A1111_DIR"

git fetch --tags origin
git checkout "$A1111_REF"

if [ ! -x "$VENV_PATH/bin/python" ]; then
  echo "[HooliPods A1111] Creating venv in volume..."
  python3.10 -m venv "$VENV_PATH"
fi

source "$VENV_PATH/bin/activate"

echo "[HooliPods A1111] Installing/updating bootstrap Python deps..."
python -m pip install --upgrade "pip<25.3" "setuptools==69.5.1" wheel

echo "[HooliPods A1111] Installing PyTorch CUDA 12.8 into volume venv..."
pip install torch torchvision torchaudio --index-url "$TORCH_INDEX_URL"

echo "[HooliPods A1111] Preinstalling OpenAI CLIP without build isolation..."
pip install --no-build-isolation "https://github.com/openai/CLIP/archive/d50d76daa670286dd6cacf3bcd80b5e4823fc8e1.zip"

cat > "$A1111_DIR/webui-user.sh" <<EOF
#!/usr/bin/env bash
export python_cmd="$VENV_PATH/bin/python"
export venv_dir="$VENV_PATH"
export COMMANDLINE_ARGS="$COMMANDLINE_ARGS"
export TORCH_COMMAND="pip install torch torchvision torchaudio --index-url $TORCH_INDEX_URL"
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
rm -rf "$A1111_DIR/outputs"

ln -s "$WORKSPACE/models/Stable-diffusion" "$A1111_DIR/models/Stable-diffusion"
ln -s "$WORKSPACE/models/Lora" "$A1111_DIR/models/Lora"
ln -s "$WORKSPACE/models/VAE" "$A1111_DIR/models/VAE"
ln -s "$WORKSPACE/models/ControlNet" "$A1111_DIR/models/ControlNet"
ln -s "$WORKSPACE/embeddings" "$A1111_DIR/embeddings"
ln -s "$OUTPUT_DIR" "$A1111_DIR/outputs"

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

echo "[HooliPods A1111] Starting A1111 on :7860"
bash "$A1111_DIR/webui.sh" -f 2>&1 | tee "$WORKSPACE/logs/webui.log"
