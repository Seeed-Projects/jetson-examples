import os
import subprocess
import sys


def path_of_script(name):
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
            subprocess.run(["bash", path_of_script("run.sh"), example_name])
        elif sys.argv[1] == "clean":
            example_name = sys.argv[2]
            subprocess.run(["bash", path_of_script("clean.sh"), example_name])
        else:
            print("Only Support `run` or `clean` for now. try `reComputer run llava` .")
    elif len(sys.argv) == 2:
        if sys.argv[1] == "check":
            subprocess.run(["bash", path_of_script("check.sh")])
        elif sys.argv[1] == "update":
            subprocess.run(["bash", path_of_script("update.sh")])
        elif sys.argv[1] == "list":
            example_folder = os.path.join(os.path.dirname(__file__), "scripts")
            directories = list_all_examples(example_folder)
            print("example list:")
            index = 1
            for directory in directories:
                print("{:03d}".format(index), "|", directory)
                index += 1
            print("-end-")
        else:
            print("reComputer help:")
            print("---")
            print("`reComputer check`   | check system.")
            print("`reComputer update`  | update jetson-ai-lab.")
            print("`reComputer list`    | list all examples.")
            print("`reComputer run xxx` | run an example.")
            print("`reComputer clean xxx` | clean an example's data.")
            print("---")
    else:
        print("Error Usage! try `reComputer help`.")


if __name__ == "__main__":
    pass
