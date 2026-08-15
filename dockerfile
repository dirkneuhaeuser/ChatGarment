FROM runpod/pytorch:2.4.0-py3.11-cuda12.4.1-devel-ubuntu22.04

RUN apt-get update && apt-get install -y git build-essential

WORKDIR /opt/ChatGarment

COPY . .

RUN pip install --upgrade pip
RUN pip install -e ".[train]"

ENV TORCH_CUDA_ARCH_LIST="8.0;8.6;8.9;9.0"
RUN pip install flash-attn==2.5.8 --no-build-isolation

RUN git clone https://github.com/biansy000/GarmentCodeRC.git /opt/garment_code
RUN pip install -e /opt/garment_code

ENV PYTHONPATH="/opt/garment_code"

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

WORKDIR /opt/ChatGarment
