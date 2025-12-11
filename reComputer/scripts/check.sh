#!/bin/bash

script_dir=$(dirname "$0")

echo "================================"
echo "    System Check Results"
echo "================================"
echo ""

# Check Docker
echo -n "Docker: "
if command -v docker &> /dev/null; then
    docker --version
else
    echo "Not installed"
fi

# Check Python3
echo -n "Python3: "
if command -v python3 &> /dev/null; then
    python3 -V
else
    echo "Not installed"
fi

# Check Python
echo -n "Python: "
if command -v python &> /dev/null; then
    python -V
else
    echo "Not installed (optional)"
fi

# Run Jetson compatibility check
if [ -f "$script_dir/jetson_compatibility.py" ]; then
    python3 "$script_dir/jetson_compatibility.py"
fi

echo ""
echo "Script directory: $script_dir"