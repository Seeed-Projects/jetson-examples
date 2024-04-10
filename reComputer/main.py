import os
import subprocess
import sys


def get_installation_path():
    script_path = os.path.abspath(sys.argv[0])
    installation_path = os.path.dirname(script_path)
    print("installation_path:", installation_path)
    return installation_path


def run_script():
    installation_path = get_installation_path()
    # TODO: maybe use python instead of shell is better
    if sys.argv[1] == "run":
        runner_script = os.path.join(installation_path, "..", "scripts", "run.sh")
        subprocess.run(["bash", runner_script, sys.argv[2]])
    else:
        script_file = os.path.join(
            installation_path, "..", "scripts", sys.argv[2] + ".sh"
        )
        subprocess.run(["bash", "new-run.sh", script_file])


def check_python():
    subprocess.run(["python3", "-V"])


if __name__ == "__main__":
    pass
