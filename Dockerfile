FROM nvidia/cuda:12.8.1-cudnn-devel-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1
ENV PYTHONNOUSERSITE=1
ENV PIP_NO_CACHE_DIR=1
ENV PIP_DISABLE_PIP_VERSION_CHECK=1

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.10 python3.10-dev python3.10-venv python3-pip \
    git git-lfs curl wget aria2 ca-certificates \
    build-essential pkg-config cmake ninja-build \
    libcairo2-dev python3-dev \
    ffmpeg libgl1 libglib2.0-0 libsm6 libxext6 libxrender1 libgoogle-perftools4 \
    unzip p7zip-full nano htop tmux procps bc \
    && rm -rf /var/lib/apt/lists/*

RUN python3.10 -m pip install --upgrade "pip<25.3" "setuptools==69.5.1" wheel

RUN curl -fsSL https://raw.githubusercontent.com/filebrowser/get/master/get.sh | bash

RUN python3.10 -m pip install jupyterlab ipykernel

COPY scripts/start_all.sh /opt/hoolipods/start_all.sh
COPY scripts/healthcheck.sh /opt/hoolipods/healthcheck.sh

RUN sed -i 's/\r$//' /opt/hoolipods/*.sh \
    && chmod +x /opt/hoolipods/*.sh

WORKDIR /workspace

EXPOSE 7860 8080 8888

HEALTHCHECK --interval=30s --timeout=10s --start-period=300s --retries=5 \
  CMD /opt/hoolipods/healthcheck.sh

CMD ["bash", "/opt/hoolipods/start_all.sh"]