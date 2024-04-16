#!/bin/bash
./run.sh $(./autotag llava) \
python3 -m llava.serve.cli \
--model-path liuhaotian/llava-v1.5-7b \
--image-file /data/images/hoover.jpg