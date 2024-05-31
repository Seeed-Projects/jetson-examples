FROM dustynv/l4t-pytorch:r35.3.1
WORKDIR /opt

RUN pip3 install --no-cache-dir --verbose gradio==4.31.5

RUN git clone https://github.com/THU-MIG/yolov10.git && \
    cd yolov10 && \
    sed -i '/opencv-python>=4.6.0/ s/^/# /' pyproject.toml && \ 
    sed -i '/torch>=1.8.0/ s/^/# /' pyproject.toml && \ 
    sed -i '/torchvision>=0.9.0/ s/^/# /' pyproject.toml && \ 
    pip3 install -e . && \
    mkdir weights 

CMD cd /opt/yolov10 && ls weights && python3 app.py