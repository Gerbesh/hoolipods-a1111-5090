# HooliPods A1111 RTX 5090

Light RunPod-ready bootstrap image for Automatic1111.

## Architecture

Docker image contains:
- CUDA base image
- system packages
- FileBrowser
- Jupyter
- startup scripts

Persistent /workspace volume contains:
- Automatic1111
- Python venv
- Torch / CUDA Python wheels
- extensions
- models
- outputs
- configs
- logs

## Ports

- 7860 - Automatic1111
- 8080 - FileBrowser
- 8888 - JupyterLab

## Run locally

docker run --rm -it --gpus all `
  --name hoolipods-a1111-test `
  -e USER_NAME=PAVEL `
  -p 7860:7860 `
  -p 8080:8080 `
  -p 8888:8888 `
  -v D:\RunPodTest\a1111-workspace:/workspace `
  hoolipods-a1111-5090:local
