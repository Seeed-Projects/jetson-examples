script_dir=$(dirname "$0")
docker --version && \
python3 -V && \
python -V && \
echo "now we can use more shell in $script_dir"