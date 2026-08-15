FROM runpod/pytorch:2.4.0-py3.11-cuda12.4.1-devel-ubuntu22.04

# libcairo2 for cairocffi (pygarment's SVG pattern rendering); libgl1/libglib2.0-0
# for opencv; libegl1/libgles2/libglvnd0 for pyrender's headless EGL backend.
RUN apt-get update && apt-get install -y \
      git build-essential libcairo2 libgl1 libglib2.0-0 \
      libegl1 libgles2 libglvnd0 \
 && rm -rf /var/lib/apt/lists/*

ENV PYOPENGL_PLATFORM=egl

# Pass a commit SHA to bust the cache: --build-arg CHATGARMENT_REF=$(git rev-parse HEAD)
ARG CHATGARMENT_REF=main
RUN git clone https://github.com/dirkneuhaeuser/ChatGarment.git /opt/ChatGarment \
 && git -C /opt/ChatGarment checkout ${CHATGARMENT_REF}

WORKDIR /opt/ChatGarment

RUN pip install --upgrade pip
RUN pip install -e ".[train]"

ENV TORCH_CUDA_ARCH_LIST="8.0;8.6;8.9;9.0"
# Prebuilt wheel. NOTE: `pip install -e ".[train]"` above pins torch 2.1.2+cu121,
# downgrading the base image's 2.4 — so the wheel must be torch2.1, not torch2.4.
# abiFALSE matches torch._C._GLIBCXX_USE_CXX11_ABI == False.
RUN pip install "https://github.com/Dao-AILab/flash-attention/releases/download/v2.5.8/flash_attn-2.5.8+cu122torch2.1cxx11abiFALSE-cp311-cp311-linux_x86_64.whl"

RUN git clone https://github.com/biansy000/GarmentCodeRC.git /opt/garment_code
RUN pip install -e /opt/garment_code
# pygarment calls igl.facet_components() expecting a flat array; libigl 2.6+ returns
# (n,1), which breaks UV unwrapping in meshgen/render/texture_utils.py.
RUN pip install "libigl==2.5.1"

# pygarment's cloth sim needs a *custom fork* of NVIDIA Warp (not pip's warp-lang).
# No wheels are published, so build it from source. Needs nvcc (present in the -devel
# base) and git-lfs; no GPU required at build time.
RUN apt-get update && apt-get install -y git-lfs && rm -rf /var/lib/apt/lists/* \
 && git lfs install
RUN git clone https://github.com/maria-korosteleva/NvidiaWarp-GarmentCode.git /opt/warp \
 && cd /opt/warp \
 && chmod +x tools/packman/packman \
 && CUDA_PATH=/usr/local/cuda python build_lib.py --cuda_path=/usr/local/cuda \
 && pip install -e /opt/warp

ENV PYTHONPATH="/opt/garment_code"
# Cache HF downloads (base LLaVA + CLIP tower) on the network volume, not the ephemeral container disk.
ENV HF_HOME="/workspace/hf"

WORKDIR /opt/garment_code
RUN cp system.template.json system.json
RUN mkdir -p Logs datasets datasets_sim body_samples
RUN sed -i \
  -e 's|"output": ".*"|"output": "/opt/garment_code/Logs/"|' \
  -e 's|"datasets_path": ".*"|"datasets_path": "/opt/garment_code/datasets/"|' \
  -e 's|"datasets_sim": ".*"|"datasets_sim": "/opt/garment_code/datasets_sim/"|' \
  -e 's|"sim_configs_path": ".*"|"sim_configs_path": "/opt/garment_code/assets/Sim_props"|' \
  -e 's|"bodies_default_path": ".*"|"bodies_default_path": "/opt/garment_code/assets/bodies"|' \
  -e 's|"body_samples_path": ".*"|"body_samples_path": "/opt/garment_code/body_samples/"|' \
  system.json

RUN ln -s /opt/garment_code/assets /opt/ChatGarment/assets

# Scripts hardcode a relative "checkpoints/..." path; point it at the network volume.
# Dangling at build time, resolves once /workspace is mounted.
RUN ln -s /workspace/checkpoints /opt/ChatGarment/checkpoints

# Keep inference outputs on the volume so they survive pod termination.
RUN ln -s /workspace/runs /opt/ChatGarment/runs

WORKDIR /opt/ChatGarment
