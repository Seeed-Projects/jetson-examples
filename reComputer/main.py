import os
import subprocess
import sys


def script(name):
    script_path = os.path.join(os.path.dirname(__file__), "scripts", name)
    return script_path


def run_script():
    # TODO: maybe use python instead of shell is better
    if len(sys.argv) == 3:
        if sys.argv[1] == "run":
            example_name = sys.argv[2]
            subprocess.run(["bash", script("run.sh"), example_name])
        else:
            print("Only Support `run` for now. try `reComputer run llava` .")
    elif len(sys.argv) == 2:
        if sys.argv[1] == "check":
            subprocess.run(["bash", script("check.sh")])
        else:
            print("Only Support `check` for now. try `reComputer check` .")
    else:
        print("Error Usage! try `reComputer run xxx` .")


if __name__ == "__main__":
    pass
