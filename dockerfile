FROM runpod/pytorch:2.4.0-py3.11-cuda12.4.1-devel-ubuntu22.04

RUN apt-get update && apt-get install -y git build-essential

ARG CHATGARMENT_REF=main
RUN git clone --depth 1 --branch ${CHATGARMENT_REF} \
      https://github.com/dirkneuhaeuser/ChatGarment.git /opt/ChatGarment

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

WORKDIR /opt/ChatGarment
