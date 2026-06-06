FROM nvidia/cuda:12.8.1-cudnn-devel-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1
ENV PYTHONNOUSERSITE=1
ENV PIP_NO_CACHE_DIR=1
ENV PIP_DISABLE_PIP_VERSION_CHECK=1

ARG PYTHON_VERSION=3.11.15
ARG TORCH_VERSION=2.9.1+cu128
ARG TORCHVISION_VERSION=0.24.1+cu128
ARG TORCHAUDIO_VERSION=2.9.1+cu128
ARG XFORMERS_VERSION=0.0.33

ENV PYTHON311_PREFIX=/opt/python/${PYTHON_VERSION}
ENV TORCH_VERSION=${TORCH_VERSION}
ENV TORCHVISION_VERSION=${TORCHVISION_VERSION}
ENV TORCHAUDIO_VERSION=${TORCHAUDIO_VERSION}
ENV XFORMERS_VERSION=${XFORMERS_VERSION}
ENV TORCH_INDEX_URL=https://download.pytorch.org/whl/cu128

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.10 python3.10-dev python3.10-venv python3-pip \
    git git-lfs curl wget aria2 ca-certificates \
    build-essential pkg-config cmake ninja-build \
    libcairo2-dev python3-dev \
    ffmpeg libgl1 libglib2.0-0 libsm6 libxext6 libxrender1 libgoogle-perftools4 \
    unzip p7zip-full nano htop tmux procps bc \
    && rm -rf /var/lib/apt/lists/*

RUN python3.10 -m pip install --upgrade "pip<25.3" "setuptools==69.5.1" wheel

RUN apt-get update && apt-get install -y --no-install-recommends \
    libbz2-dev libffi-dev libgdbm-dev liblzma-dev libncursesw5-dev \
    libreadline-dev libsqlite3-dev libssl-dev tk-dev uuid-dev zlib1g-dev \
    && curl -fsSL "https://www.python.org/ftp/python/${PYTHON_VERSION}/Python-${PYTHON_VERSION}.tgz" -o /tmp/Python.tgz \
    && mkdir -p /tmp/python-src \
    && tar -xzf /tmp/Python.tgz -C /tmp/python-src --strip-components=1 \
    && cd /tmp/python-src \
    && ./configure --prefix="${PYTHON311_PREFIX}" --enable-shared --with-ensurepip=install LDFLAGS="-Wl,-rpath,${PYTHON311_PREFIX}/lib" \
    && make -j"$(nproc)" \
    && make install \
    && ln -sf "${PYTHON311_PREFIX}/bin/python3.11" /usr/local/bin/python3.11 \
    && ln -sf "${PYTHON311_PREFIX}/bin/pip3.11" /usr/local/bin/pip3.11 \
    && "${PYTHON311_PREFIX}/bin/python3.11" -m pip install --no-cache-dir --upgrade "pip<25.3" "setuptools==69.5.1" wheel \
    && rm -rf /tmp/Python.tgz /tmp/python-src /var/lib/apt/lists/*

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
