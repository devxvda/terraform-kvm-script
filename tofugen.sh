#!/bin/bash
export HCL_FILE=main.tf

if [[ -z "$1" ]]; then
    echo "First argument should be output directory"
else
    if [[ -d "$1" ]]; then
        echo "Error: Directory Exist!"
        exit 1
    else
        export TMP_DIR="$1"
        if [[ -z "$2" ]]; then
            echo "Second argument should be environment file"
        else
            if [[ ! -f "$2" ]]; then
                echo "File environment does not exist"
            else
                export ENV_FILE="$2"
                source function/gentemplate.sh
                generate_template
            fi
        fi
    fi
fi
