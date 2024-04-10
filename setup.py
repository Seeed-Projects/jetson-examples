from setuptools import setup

setup(
    name="reComputer",
    version="1.0",
    install_requires=["docker"],
    data_files=[("scripts", ["scripts/run.sh"])],
    entry_points={
        "console_scripts": [
            "reComputer = reComputer.main:run_script",
        ]
    },
)
