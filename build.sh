#!/bin/bash

# 1 try clean older version
pip uninstall jetson-examples -y

# 2 clean last build files
rm -rf build/

# 4 find and rm /images direct
find . -name "images" -type d -exec rm -rf {} +

# 3 install latest version
pip install .

# 4 build whl
read -p "build whl ? (y/n): " choice
if [[ $choice == "y" || $choice == "Y" ]]; then
    python3 -m pip install --upgrade build
    echo "building..."
    rm -rf dist/
    python3 -m build
    echo "build done."
else
    echo "skip build."
fi

# 5 publish to Test PyPI
read -p "publish to test PyPI ? (y/n): " choice
if [[ $choice == "y" || $choice == "Y" ]]; then
    python3 -m pip install --upgrade twine
    keyring --disable # https://github.com/pypa/twine/issues/847
    echo "publishing to Test PyPI..."
    python3 -m twine upload --repository testpypi dist/*
else
    echo "skip publish."
fi


# 6 publish to PyPI
read -p "[Danger!!] publish to PyPI ? (confirm/*): " choice
if [[ $choice == "confirm" || $choice == "CONFIRM" ]]; then
    python3 -m pip install --upgrade twine
    keyring --disable # https://twine.readthedocs.io/en/stable/#disabling-keyring
    echo "publishing to Prod PyPI..."
    python3 -m twine upload --repository pypi dist/*
else
    echo "skip publish."
fi

echo 'clean & build & publish ok.'
