#!/bin/bash

# --- Configuration ---
#
# Docker run options
DOCKER_OPTS="-d --label tsdproxy.enable=true"

# Set the path inside the container where the user's workspace will be mounted.
CONTAINER_WORKSPACE_PATH="/workspace"

VNC_START_PORT=5000
NOVNC_START_PORT=6000

# Exit immediately if a command fails
set -e

# 1. Check if an input file was provided
INPUT_FILE="$1"
if [[ -z "$INPUT_FILE" ]]; then
    echo "Usage: $0 <user_image_file.txt>" >&2
    echo "Error: You must provide a file listing users and their images." >&2
    exit 1
fi

if [[ ! -f "$INPUT_FILE" ]]; then
    echo "Error: File not found: $INPUT_FILE" >&2
    exit 1
fi

# 2. Get the absolute path of the directory this script is in
# This ensures 'ws_[name]' folders are created relative to the script
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# 3. Read the input file line by line
# Expected format: username image_name
i=1
while read -r username image_name; do
    
    # Skip empty lines or lines that start with a # (comments)
    if [[ -z "$username" || "$username" == \#* ]]; then
        continue
    fi

    echo "--- Processing user: $username ---"

    # Define container and volume names
    CONTAINER_NAME="dev-$username"
    VOLUME_DIR_NAME="ws_$username"
    HOST_VOLUME_PATH="$SCRIPT_DIR/$VOLUME_DIR_NAME"

    # 4. Create the shared volume folder
    echo "Creating host directory: $HOST_VOLUME_PATH"
    mkdir -p "$HOST_VOLUME_PATH"

    # 5. Define the user-specific volume option
    USER_VOLUME_OPT="-v $HOST_VOLUME_PATH:$CONTAINER_WORKSPACE_PATH"

    VNC_PORT=$((VNC_START_PORT + i))
    NOVNC_PORT=$((NOVNC_START_PORT + i))
    PORT_OPT="--label tsdproxy.name=$username --label tsdproxy.port.1=5901/tcp:5901/tcp,noautodetect,no_tlsvalidate -p $VNC_PORT:5901 --label tsdproxy.port.2=6080/tcp:6080/tcp,noautodetect,no_tlsvalidate -p $NOVNC_PORT:6080"

    # 7. Check if a container with this name is already running
    if [ "$(docker ps -q -f name=^/${CONTAINER_NAME}$)" ]; then
        echo "Container $CONTAINER_NAME is already running. Stopping and removing it."
        docker stop "$CONTAINER_NAME" > /dev/null
    fi
    if [ "$(docker ps -aq -f name=^/${CONTAINER_NAME}$)" ]; then
        echo "Container $CONTAINER_NAME exists. Removing it."
        docker rm "$CONTAINER_NAME" > /dev/null
    fi

    # 8. Run the new container
    echo "Starting container '$CONTAINER_NAME' using image '$image_name'..."
    docker run $DOCKER_OPTS \
             $USER_VOLUME_OPT \
	     $PORT_OPT \
             --name "$CONTAINER_NAME" \
             "$image_name"

    echo "Successfully launched $CONTAINER_NAME"
    echo ""
    i=$((i + 1))
done < "$INPUT_FILE"

echo "All containers have been processed."
