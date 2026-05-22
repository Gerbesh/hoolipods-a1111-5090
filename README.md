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

## Environment

- `USER_NAME` or `HOOLIPODS_USER_NAME` - user folder name for outputs.
- `WORKSPACE` - volume mount path, defaults to `/workspace`.
- `OUTPUTS_ROOT` - output root, defaults to `/workspace/outputs`.
- `USER_DATA_ROOT` - per-user A1111 settings root, defaults to `/workspace/userdata/a1111`.

The container validates `USER_NAME` and writes A1111 outputs to:

```text
/workspace/outputs/<USER_NAME>
```

A1111 per-user config/data is stored separately in:

```text
/workspace/userdata/a1111/<USER_NAME>
```

Allowed `USER_NAME` characters: letters, digits, `.`, `_`, `-`, `@`.

## Run locally

docker run --rm -it --gpus all `
  --name hoolipods-a1111-test `
  -e USER_NAME=PAVEL `
  -p 7860:7860 `
  -p 8080:8080 `
  -p 8888:8888 `
  -v D:\RunPodTest\a1111-workspace:/workspace `
  hoolipods-a1111-5090:local
