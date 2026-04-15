#!/bin/bash

# check the runtime environment.
source $(dirname "$(realpath "$0")")/../utils.sh
check_base_env "$(dirname "$(realpath "$0")")/config.yaml"
