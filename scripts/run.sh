#!/bin/bash

check_is_jetson_or_not() {
    model_file="/proc/device-tree/model"

    if [ -f "$model_file" ]; then
        first_line=$(head -n 1 "$model_file")

        if [[ "$first_line" == NVIDIA* ]]; then
            echo "INFO: jetson machine confirmed..."
        else
            echo "WARNING: your machine maybe not support..."
            exit 1
        fi
    else
        echo "ERROR: only jetson support this..."
        exit 1
    fi
}
check_is_jetson_or_not

check_disk_space() {
    directory="$1"  # a directory
    required_space_gb="$2"  # how many GB we need
    
    # get disk of directory
    device=$(df -P "$directory" | awk 'NR==2 {print $1}')
    echo $device
    
    # get free space in KB
    free_space=$(df -P "$device" | awk 'NR==2 {print $4}')
    echo $free_space
    
    # change unit to GB
    free_space_gb=$(echo "scale=2; $free_space / 1024 / 1024" | bc)
    echo $free_space_gb
    
    # check and fast-fail
    if (( $(echo "$free_space_gb >= $required_space_gb" | bc -l) )); then
        echo "disk space ($1) enough, keep going."
    else
        echo "disk space ($1) not enough!! we need $2 GB!!"
        exit 1
    fi
}

echo "run example：$1"
BASE_PATH=/home/$USER/reComputer
echo "----example init----"
mkdir -p $BASE_PATH/
JETSON_REPO_PATH="$BASE_PATH/jetson-containers"
if [ -d $JETSON_REPO_PATH ]; then
    echo "jetson-ai-lab existed."
else
    echo "jetson-ai-lab does not installed. start init..."
    cd $BASE_PATH/
    git clone --depth=1 https://github.com/dusty-nv/jetson-containers
    cd $JETSON_REPO_PATH
    sudo apt update; sudo apt install -y python3-pip
    pip3 install -r requirements.txt
fi
echo "----example start----"
cd $JETSON_REPO_PATH
case "$1" in
    "llava")
        ./run.sh $(./autotag llava) \
        python3 -m llava.serve.cli \
        --model-path liuhaotian/llava-v1.5-7b \
        --image-file /data/images/hoover.jpg
    ;;
    "llava-v1.5-7b")
        ./run.sh $(./autotag llava) \
        python3 -m llava.serve.cli \
        --model-path liuhaotian/llava-v1.5-7b \
        --image-file /data/images/hoover.jpg
    ;;
    "llava-v1.6-vicuna-7b")
        ./run.sh $(./autotag local_llm) \
        python3 -m local_llm --api=mlc \
        --model liuhaotian/llava-v1.6-vicuna-7b \
        --max-context-len 768 \
        --max-new-tokens 128
    ;;
    "Sheared-LLaMA-2.7B-ShareGPT")
        ./run.sh $(./autotag local_llm) \
        python3 -m local_llm.chat --api=mlc \
        --model princeton-nlp/Sheared-LLaMA-2.7B-ShareGPT
    ;;
    "text-generation-webui")
        # download llm model
        ./run.sh --workdir=/opt/text-generation-webui $(./autotag text-generation-webui) /bin/bash -c \
        'python3 download-model.py --output=/data/models/text-generation-webui TheBloke/Llama-2-7b-Chat-GPTQ'
        # run text-generation-webui
        ./run.sh $(./autotag text-generation-webui)
    ;;
    "stable-diffusion-webui")
        ./run.sh $(./autotag stable-diffusion-webui)
    ;;
    "nanoowl")
        ./run.sh $(./autotag nanoowl) bash -c "ls /dev/video* && cd examples/tree_demo && python3 tree_demo.py ../../data/owl_image_encoder_patch32.engine"
    ;;
    "whisper")
        ./run.sh $(./autotag whisper)
    ;;
    "nanodb")
        # check data files TODO: support params to force download
        DATA_PATH="$JETSON_REPO_PATH/data/datasets/coco/2017"
        if [ ! -d $DATA_PATH ]; then
            mkdir -p $DATA_PATH
        fi
        cd $DATA_PATH
        # check val2017.zip
        if [ ! -d "$DATA_PATH/val2017" ]; then
            if [ ! -f "val2017.zip" ]; then
                check_disk_space $DATA_PATH 1
                wget http://images.cocodataset.org/zips/val2017.zip
            else
                echo "val2017.zip existed."
            fi
            check_disk_space $DATA_PATH 19
            unzip val2017.zip && rm val2017.zip
        else
            echo "val2017/ existed."
        fi
        # check train2017.zip
        if [ ! -d "$DATA_PATH/train2017" ]; then
            if [ ! -f "train2017.zip" ]; then
                check_disk_space $DATA_PATH 19
                wget http://images.cocodataset.org/zips/train2017.zip
            else
                echo "train2017.zip existed."
            fi
            check_disk_space $DATA_PATH 19
            unzip train2017.zip && rm train2017.zip
        else
            echo "train2017/ existed."
        fi
        if [ ! -d "$DATA_PATH/unlabeled2017" ]; then
            # check unlabeled2017.zip
            if [ ! -f "unlabeled2017.zip" ]; then
                check_disk_space $DATA_PATH 19
                wget http://images.cocodataset.org/zips/unlabeled2017.zip
            else
                echo "unlabeled2017.zip existed."
            fi
            check_disk_space $DATA_PATH 19
            unzip unlabeled2017.zip && rm unlabeled2017.zip
        else
            echo "unlabeled2017/ existed."
        fi
        
        # check index files
        INDEX_PATH="$JETSON_REPO_PATH/data/nanodb/coco/2017"
        if [ ! -d $INDEX_PATH ]; then
            cd $JETSON_REPO_PATH/data/
            check_disk_space $JETSON_REPO_PATH 1
            wget https://nvidia.box.com/shared/static/icw8qhgioyj4qsk832r4nj2p9olsxoci.gz -O nanodb_coco_2017.tar.gz
            tar -xzvf nanodb_coco_2017.tar.gz
        fi
        
        # RUN
        cd $JETSON_REPO_PATH
        ./run.sh $(./autotag nanodb) \
        python3 -m nanodb \
        --path /data/nanodb/coco/2017 \
        --server --port=7860
    ;;
    "live-llava")
        SUPPORT_L4T_LIST="35.3.1"
        BASE_PATH=/home/$USER/reComputer
        JETSON_REPO_PATH="$BASE_PATH/jetson-containers"

        get_l4t_version() {
            ARCH=$(uname -i)
            echo "ARCH:  $ARCH"

            if [ $ARCH = "aarch64" ]; then
                L4T_VERSION_STRING=$(head -n 1 /etc/nv_tegra_release)

                if [ -z "$L4T_VERSION_STRING" ]; then
                    echo "reading L4T version from \"dpkg-query --show nvidia-l4t-core\""
                    L4T_VERSION_STRING=$(dpkg-query --showformat='${Version}' --show nvidia-l4t-core)
                    L4T_VERSION_ARRAY=(${L4T_VERSION_STRING//./ })
                    L4T_RELEASE=${L4T_VERSION_ARRAY[0]}
                    L4T_REVISION=${L4T_VERSION_ARRAY[1]}
                else
                    echo "reading L4T version from /etc/nv_tegra_release"
                    L4T_RELEASE=$(echo $L4T_VERSION_STRING | cut -f 2 -d ' ' | grep -Po '(?<=R)[^;]+')
                    L4T_REVISION=$(echo $L4T_VERSION_STRING | cut -f 2 -d ',' | grep -Po '(?<=REVISION: )[^;]+')
                fi

                L4T_REVISION_MAJOR=${L4T_REVISION:0:1}
                L4T_REVISION_MINOR=${L4T_REVISION:2:1}
                L4T_VERSION="$L4T_RELEASE.$L4T_REVISION"

                echo "L4T_VERSION:  $L4T_VERSION"

            elif [ $ARCH != "x86_64" ]; then
                echo "unsupported architecture:  $ARCH" # show in red color
                exit 1
            fi
        }

        # 1. Check L4T version
        get_l4t_version
        CHECK_L4T_VERSION=0
        for item in $SUPPORT_L4T_LIST; do
            if [ "$item" = "$L4T_VERSION" ]; then
                CHECK_L4T_VERSION=1
                break
            fi
        done

        if [ $CHECK_L4T_VERSION -eq 1 ]; then
            echo "pass the version check"
        else
            echo "currently supported versions of jetpack are $SUPPORT_L4T_LIST" # show in red color
            exit 1
        fi

        # 2. Check Google Chrome
        if dpkg -s chromium-browser &>/dev/null; then
            echo "Chrome is installed."
        else
            echo "install Google Chrome ..." # show in red color
            sudo apt install chromium-browser
            echo "Google Chrome installed successfully" # show in red color
        fi

        # 3. Generate Google browser key
        FILE_NAME="key.pem"
        FILE_PATH="$JETSON_REPO_PATH/data"
        if [ -f "$FILE_PATH/$FILE_NAME" ]; then
            echo "key file '$FILE_PATH/$FILE_NAME' exists."
        else
            cd $FILE_PATH
            openssl req -x509 -newkey rsa:4096 -keyout key.pem -out cert.pem -sha256 -days 365 -nodes -subj '/CN=localhost'
            cd ..
        fi

        # 4. edit source code
cat >"$JETSON_REPO_PATH/packages/llm/local_llm/agents/video_query.py" <<'EOF'
#!/usr/bin/env python3
import time
import logging
import threading

from local_llm import Agent

from local_llm.plugins import (
    VideoSource,
    VideoOutput,
    ChatQuery,
    PrintStream,
    ProcessProxy,
)
from local_llm.utils import ArgParser, print_table

from termcolor import cprint
from jetson_utils import cudaFont, cudaMemcpy, cudaToNumpy, cudaDeviceSynchronize

from flask import Flask, request


class VideoQuery(Agent):
    """
    Perpetual always-on closed-loop visual agent that applies prompts to a video stream.
    """

    def __init__(self, model="liuhaotian/llava-v1.5-7b", **kwargs):
        super().__init__()
        self.lock = threading.Lock()

        # load model in another process for smooth streaming
        # self.llm = ProcessProxy((lambda **kwargs: ChatQuery(model, drop_inputs=True, **kwargs)), **kwargs)
        self.llm = ChatQuery(model, drop_inputs=True, **kwargs)
        self.llm.add(PrintStream(color="green", relay=True).add(self.on_text))
        self.llm.start()

        # test / warm-up query
        self.warmup = True
        self.text = ""
        self.eos = False

        self.llm("What is 2+2?")

        while self.warmup:
            time.sleep(0.25)

        # create video streams
        self.video_source = VideoSource(**kwargs)
        self.video_output = VideoOutput(**kwargs)

        self.video_source.add(self.on_video, threaded=False)
        self.video_output.start()

        self.font = cudaFont()

        # setup prompts
        self.prompt = "Describe the image concisely and briefly."

        # entry node
        self.pipeline = [self.video_source]

    def on_video(self, image):
        np_image = cudaToNumpy(image)
        cudaDeviceSynchronize()

        self.llm(
            [
                "reset",
                np_image,
                self.prompt,
            ]
        )

        text = self.text.replace("\n", "").replace("</s>", "").strip()

        if text:
            worlds = text.split()
            line_counter = len(worlds) // 10
            if len(worlds) % 10 != 0:
                line_counter += 1
            for l in range(line_counter):
                line_text = " ".join(worlds[l * 10 : (l + 1) * 10])
                self.font.OverlayText(
                    image,
                    text=line_text,
                    x=5,
                    y=int(79 + l * 37),
                    color=self.font.White,
                    background=self.font.Gray40,
                )
        self.font.OverlayText(
            image,
            text="Prompt: " + self.prompt,
            x=5,
            y=42,
            color=(120, 215, 21),
            background=self.font.Gray40,
        )
        self.video_output(image)

    def on_text(self, text):
        if self.eos:
            self.text = text  # new query response
            self.eos = False
        elif not self.warmup:  # don't view warmup response
            self.text = self.text + text

        if text.endswith("</s>") or text.endswith("###") or text.endswith("<|im_end|>"):
            self.print_stats()
            self.warmup = False
            self.eos = True

    def update_switch(self, on_off):
        self.video_source.switch(on_off)

    def update_prompts(self, new_prompt):
        with self.lock:
            if new_prompt:
                self.prompt = new_prompt

    def print_stats(self):
        # print_table(self.llm.model.stats)
        curr_time = time.perf_counter()

        if not hasattr(self, "start_time"):
            self.start_time = curr_time
        else:
            frame_time = curr_time - self.start_time
            self.start_time = curr_time
            logging.info(
                f"refresh rate:  {1.0 / frame_time:.2f} FPS  ({frame_time*1000:.1f} ms)"
            )


if __name__ == "__main__":
    parser = ArgParser(extras=ArgParser.Defaults + ["video_input", "video_output"])
    args = parser.parse_args()
    # 独立线程运行
    agent = VideoQuery(**vars(args))

    def run_video_query():
        agent.run()

    video_query_thread = threading.Thread(target=run_video_query)
    video_query_thread.start()

    # 启动web服务
    app = Flask(__name__)

    @app.route("/update_prompt", methods=["POST"])
    def update_prompts():
        prompt = request.json.get("prompt")
        if prompt:
            agent.update_prompts(prompt)
            return "Prompts updated successfully."
        else:
            return "Invalid prompts data."

    @app.route("/update_switch", methods=["POST"])
    def update_switch():
        infer_or_not = True if request.json.get("switch") == "on" else False
        agent.update_switch(infer_or_not)
        return "stop" if not infer_or_not else "start"

    @app.route("/update_params", methods=["POST"])
    def update_params():
        try:
            agent.llm.max_new_tokens = request.json.get("max_new_tokens") or 128
            agent.llm.min_new_tokens = request.json.get("min_new_tokens") or -1
            agent.llm.do_sample = request.json.get("do_sample") or False
            agent.llm.repetition_penalty = request.json.get("repetition_penalty") or 1.0
            agent.llm.temperature = request.json.get("temperature") or 0.7
            agent.llm.top_p = request.json.get("top_p") or 0.95
            if request.json.get("system_prompt"):
                agent.llm.chat_history.template["system_prompt"] = request.json.get(
                    "system_prompt"
                )
            return "params updated."
        except Exception as e:
            print(e)
            return "update failure"

    app.run(host="0.0.0.0", port=5555)


EOF

    sed -i 's/from transformers import CLIPImageProcessor, CLIPVisionModelWithProjection, SiglipImageProcessor, SiglipVisionModel/from transformers import CLIPImageProcessor, CLIPVisionModelWithProjection  # , SiglipImageProcessor, SiglipVisionModel/' "$JETSON_REPO_PATH/packages/llm/local_llm/vision/clip_hf.py"
    sed -i "s/'siglip': dict(preprocessor=SiglipImageProcessor, model=SiglipVisionModel),/# 'siglip': dict(preprocessor=SiglipImageProcessor, model=SiglipVisionModel),/" "$JETSON_REPO_PATH/packages/llm/local_llm/vision/clip_hf.py"

    sed -i 's/from .audio import */# from .audio import */' "$JETSON_REPO_PATH/packages/llm/local_llm/plugins/__init__.py"
    sed -i 's/from .nanodb import NanoDB/# from .nanodb import NanoDB/' "$JETSON_REPO_PATH/packages/llm/local_llm/plugins/__init__.py"

    sed -i 's/import onnxruntime as ort/# import onnxruntime as ort/' "$JETSON_REPO_PATH/packages/llm/local_llm/utils/model.py"

    echo "The script has been modified."

    # gnome-terminal -- /bin/bash -c chromium-browser --disable-features=WebRtcHideLocalIpsWithMdns https://localhost:8554/"; exec /bin/bash"

    cd $JETSON_REPO_PATH
    sudo docker run --runtime nvidia -it --rm --network host --volume /tmp/argus_socket:/tmp/argus_socket --volume /etc/enctune.conf:/etc/enctune.conf --volume /etc/nv_tegra_release:/etc/nv_tegra_release --volume /proc/device-tree/model:/tmp/nv_jetson_model --volume /var/run/dbus:/var/run/dbus --volume /var/run/avahi-daemon/socket:/var/run/avahi-daemon/socket --volume /var/run/docker.sock:/var/run/docker.sock --volume $JETSON_REPO_PATH/data:/data --device /dev/snd --device /dev/bus/usb -e DISPLAY=:0 -v /tmp/.X11-unix/:/tmp/.X11-unix -v /tmp/.docker.xauth:/tmp/.docker.xauth -e XAUTHORITY=/tmp/.docker.xauth --device /dev/video0 --device /dev/video1 -v $JETSON_REPO_PATH/packages/llm/local_llm:/opt/local_llm/local_llm -e SSL_KEY=/data/key.pem -e SSL_CERT=/data/cert.pem dustynv/local_llm:r35.3.1 python3 -m local_llm.agents.video_query --api=mlc --verbose --model liuhaotian/llava-v1.5-7b --max-new-tokens 32 --video-input /dev/video0 --video-output webrtc://@:8554/output
    ;;
    *)
        echo "Unknown example"
        # handle unknown
    ;;
esac
echo "----example done----"
