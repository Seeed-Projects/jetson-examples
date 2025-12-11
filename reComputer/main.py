import os
import subprocess
import sys
from .config import Config


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
    # Load configuration
    config = Config()
    
    # Export configuration as environment variables for shell scripts
    env = os.environ.copy()
    env.update({
        "BASE_PATH": config.get("BASE_PATH"),
        "JETSON_REPO_PATH": config.get("JETSON_REPO_PATH"),
    })

    if len(sys.argv) == 3:
        if sys.argv[1] == "run":
            example_name = sys.argv[2]
            # TODO: maybe use python instead of shell is better
            subprocess.run(["bash", path_of_script("run.sh"), example_name], env=env)
        elif sys.argv[1] == "clean":
            example_name = sys.argv[2]
            subprocess.run(["bash", path_of_script("clean.sh"), example_name], env=env)
        elif sys.argv[1] == "list" and sys.argv[2] == "--detailed":
            # Run the table generator script
            script_path = path_of_script("generate_example_table.py")
            if os.path.exists(script_path):
                subprocess.run(["python3", script_path])
            else:
                print("Detailed table generator not found")
        else:
            print("Only Support `run` or `clean` for now. try `reComputer run llava` .")
    elif len(sys.argv) == 2:
        if sys.argv[1] == "check":
            subprocess.run(["bash", path_of_script("check.sh")], env=env)
        elif sys.argv[1] == "setup":
            subprocess.run(["bash", path_of_script("setup.sh")], env=env)
        elif sys.argv[1] == "update":
            subprocess.run(["bash", path_of_script("update.sh")], env=env)
        elif sys.argv[1] == "config":
            # Handle configuration commands
            from . import config as config_module
            config_module.main()
        elif sys.argv[1] == "list":
            # Check if detailed list is requested
            if len(sys.argv) > 2 and sys.argv[2] == "--detailed":
                # Run the table generator script
                script_path = path_of_script("generate_example_table.py")
                if os.path.exists(script_path):
                    subprocess.run(["python3", script_path])
                else:
                    print("Detailed table generator not found")
            else:
                # Simple list
                example_folder = os.path.join(os.path.dirname(__file__), "scripts")
                directories = list_all_examples(example_folder)
                print("Example list:")
                print("-" * 40)
                index = 1
                for directory in directories:
                    print("{:03d}".format(index), "|", directory)
                    index += 1
                print("-" * 40)
                print("\nFor detailed comparison: reComputer list --detailed")
        else:
            print("reComputer help:")
            print("---")
            print("`reComputer check`   | check system.")
            print("`reComputer setup`   | setup environment and install dependencies.")
            print("`reComputer config`  | manage configuration settings.")
            print("`reComputer update`  | update jetson-ai-lab.")
            print("`reComputer list`    | list all examples.")
            print("`reComputer run xxx` | run an example.")
            print("`reComputer clean xxx` | clean an example's data.")
            print("---")
            print("")
            print("Configuration commands:")
            print("  `reComputer config show`        | show current configuration")
            print("  `reComputer config set KEY VAL` | set configuration value")
            print("  `reComputer config get KEY`     | get configuration value")
            print("  `reComputer config reset`       | reset to defaults")
    else:
        print("Error Usage! try `reComputer help`.")


if __name__ == "__main__":
    pass
