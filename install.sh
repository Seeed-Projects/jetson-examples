#!/bin/bash
# TODO: make sure python3 in host is OK
cd /tmp && \
git clone https://github.com/Seeed-Projects/jetson-examples && \
cd jetson-examples && \
pip install . && \
rm -rf /tmp/jetson-examples && \
echo "reComputer installed. try 'reComputer run whisper' to enjoy!"