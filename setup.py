from pathlib import Path

from setuptools import setup


README_PATH = Path(__file__).parent / "README.md"
LONG_DESCRIPTION = README_PATH.read_text(encoding="utf-8")
PACKAGE_ROOT = Path(__file__).parent / "reComputer"


def package_files(root: Path):
    files = []
    for path in root.rglob("*"):
        if not path.is_file():
            continue
        if "__pycache__" in path.parts:
            continue
        if path.suffix in {".pyc", ".pyo"}:
            continue
        files.append(path.relative_to(PACKAGE_ROOT).as_posix())
    return sorted(files)


setup(
    name="jetson-examples",
    version="0.2.8",
    author="luozhixin",
    author_email="zhixin.luo@seeed.cc",
    description="Running Gen AI models and applications on NVIDIA Jetson devices with one-line command",
    long_description=LONG_DESCRIPTION,
    long_description_content_type="text/markdown",
    python_requires=">=3.8",
    keywords=[
        "llama",
        "llava",
        "gpt",
        "llm",
        "nvidia",
        "jetson",
        "multimodal",
        "jetson orin",
    ],
    classifiers=[
        "Programming Language :: Python :: 3",
        "License :: OSI Approved :: MIT License",
        "Operating System :: OS Independent",
    ],
    packages=["reComputer"],
    include_package_data=True,
    package_data={"reComputer": package_files(PACKAGE_ROOT / "scripts")},
    entry_points={
        "console_scripts": [
            "reComputer=reComputer.main:run_script",
        ]
    },
    project_urls={
        "Homepage": "https://github.com/Seeed-Projects/jetson-examples",
        "Issues": "https://github.com/Seeed-Projects/jetson-examples/issues",
    },
)
