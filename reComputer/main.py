import os
import subprocess
import sys


def script(name):
    script_path = os.path.join(os.path.dirname(__file__), "scripts", name)
    return script_path


def list_all_examples(folder_path):
    directory_names = []
    for item in os.listdir(folder_path):
        item_path = os.path.join(folder_path, item)
        if os.path.isdir(item_path):
            directory_names.append(item)
    return directory_names


def run_script():

    if len(sys.argv) == 3:
        if sys.argv[1] == "run":
            example_name = sys.argv[2]
            # TODO: maybe use python instead of shell is better
            subprocess.run(["bash", script("run.sh"), example_name])
        else:
            print("Only Support `run` for now. try `reComputer run llava` .")
    elif len(sys.argv) == 2:
        if sys.argv[1] == "check":
            subprocess.run(["bash", script("check.sh")])
        if sys.argv[1] == "list":
            example_folder = os.path.join(os.path.dirname(__file__), "scripts")
            directories = list_all_examples(example_folder)
            print("example list:")
            index = 1
            for directory in directories:
                print("{:03d}".format(index), "|", directory)
                index += 1
            print("-end-")
        else:
            print("Only Support `check` for now. try `reComputer check` .")
    else:
        print("Error Usage! try `reComputer run xxx` .")


if __name__ == "__main__":
    pass
