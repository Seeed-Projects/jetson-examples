#!/bin/bash
./run.sh $(./autotag local_llm) \
python3 -m local_llm --api=mlc \
--model liuhaotian/llava-v1.6-vicuna-7b \
--max-context-len 768 \
--max-new-tokens 128