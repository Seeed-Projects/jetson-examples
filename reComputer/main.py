import os
import subprocess
import sys


def get_installation_path():
    script_path = os.path.abspath(sys.argv[0])
    installation_path = os.path.dirname(script_path)
    print("installation_path:", installation_path)
    return installation_path


def run_script():
    # TODO: maybe use python instead of shell is better
    if len(sys.argv) == 3:
        if sys.argv[1] == "run":
            run_example()
        else:
            print("Only Support `run` for now. try `reComputer run llava` .")
    elif len(sys.argv) == 2:
        if sys.argv[1] == "check":
            check()
        else:
            print("Only Support `check` for now. try `reComputer check` .")
    else:
        print("Error Usage! try `reComputer run xxx` .")


def run_example():
    installation_path = get_installation_path()
    runner_script = os.path.join(installation_path, "..", "scripts", "run.sh")
    subprocess.run(["bash", runner_script, sys.argv[2]])


def check():
    # TODO: do some real check
    subprocess.run(["python", "-V"])
    subprocess.run(["python3", "-V"])


if __name__ == "__main__":
    pass
