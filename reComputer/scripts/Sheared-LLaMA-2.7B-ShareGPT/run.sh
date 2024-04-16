#!/bin/bash

./run.sh $(./autotag local_llm) \
python3 -m local_llm.chat --api=mlc \
--model princeton-nlp/Sheared-LLaMA-2.7B-ShareGPT