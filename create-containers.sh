#!/bin/bash

# --- Configuration ---
#
# Docker run options
DOCKER_OPTS="-d --label tsdproxy.enable=true --label tsbridge.enabled=true --gpus all --platform linux/amd64 --network host -e USER=ubuntu -e PASSWORD=ubuntu -e NOVNC_WEB=/usr/lib/novnc -e DISPLAY_NUM=70 -e NVIDIA_VISIBLE_DEVICES=all -e NVIDIA_DRIVER_CAPABILITIES=compute,utility,video,graphics,display -e LD_LIBRARY_PATH=/usr/local/nvidia/lib:/usr/local/nvidia/lib64:$LD_LIBRARY_PATH -e DISPLAY=$DISPLAY -e VK_ICD_FILENAMES=/etc/vulkan/icd.d/nvidia_icd.json -v /etc/vulkan/icd.d:/etc/vulkan/icd.d:ro -v /usr/share/vulkan/icd.d:/usr/share/vulkan/icd.d:ro -v /tmp/.X11-unix:/tmp/.X11-unix:rw"
# Set the path inside the container where the user's workspace will be mounted.
CONTAINER_WORKSPACE_PATH="/workspace"
# Output ports for VNC, NoVNC, and SSH
VNC_OUTPUT_PORT=5901
NOVNC_OUTPUT_PORT=6080
SSH_OUTPUT_PORT=22

VNC_START_PORT=10000
NOVNC_START_PORT=11000
SSH_START_PORT=12000

# Exit immediately if a command fails
set -e

# 1. Check arguments
MODE="$1"
INPUT_FILE="$2"

if [[ "$MODE" != "add" && "$MODE" != "recreate" ]]; then
    echo "Usage: $0 <mode> <user_image_file.txt>" >&2
    echo "Error: Invalid mode '$MODE'. Mode must be 'add' or 'recreate'." >&2
    echo "" >&2
    echo "  add       - Only create containers for new users. Skip existing containers." >&2
    echo "  recreate  - Stop and remove any existing containers before creating new ones." >&2
    exit 1
fi

if [[ -z "$INPUT_FILE" ]]; then
    echo "Usage: $0 <mode> <user_image_file.txt>" >&2
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

echo "--- Running in '$MODE' mode ---"

# 3. Read the input file line by line
# Expected format: username image_name
i=1
while read -r username image_name; do
    
    # Skip empty lines or lines that start with a # (comments)
    if [[ -z "$username" || "$username" == \#* ]]; then
        continue
    fi

    echo "--- Processing user: $username (Entry $i) ---"

    # Define container and volume names
    CONTAINER_NAME="dev-$username"
    VOLUME_DIR_NAME="ws_$username"
    HOST_VOLUME_PATH="$SCRIPT_DIR/$VOLUME_DIR_NAME"

    # 4. Create the shared volume folder
    echo "Creating host directory: $HOST_VOLUME_PATH"
    mkdir -p "$HOST_VOLUME_PATH"

    # 5. Define the user-specific volume option
    USER_VOLUME_OPT="-v $HOST_VOLUME_PATH:$CONTAINER_WORKSPACE_PATH"

    # 6. Define Port options
    # VNC
    VNC_CNT_PORT=$((VNC_START_PORT + i))
    VNC_OPT="-e VNC_PORT=$VNC_CNT_PORT --label tsdproxy.port.1=5901/tcp:$VNC_CNT_PORT/tcp,noautodetect,no_tlsvalidate"
    #VNC_OPT="-e VNC_PORT=$VNC_CNT_PORT --label tsbridge.service.port=$VNC_CNT_PORT --label tsbridge.service.listen_addr=:$VNC_OUTPUT_PORT"

    # NoVNC
    NOVNC_CNT_PORT=$((NOVNC_START_PORT + i))
    NOVNC_OPT="-e NOVNC_PORT=$NOVNC_CNT_PORT --label tsdproxy.port.2=6080/http:$NOVNC_CNT_PORT/http,noautodetect,no_tlsvalidate"
    #NOVNC_OPT="-e NOVNC_PORT=$NOVNC_CNT_PORT --label tsbridge.web.port=$NOVNC_CNT_PORT --label tsbridge.web.listen_addr=:$NOVNC_OUTPUT_PORT"

    SSH_CNT_PORT=$((SSH_START_PORT + i))
    SSH_OPT="-e SSH_PORT=$SSH_CNT_PORT --label tsdproxy.port.3=22/tcp:$SSH_CNT_PORT/tcp,noautodetect,no_tlsvalidate"
    #SSH_OPT="-e SSH_PORT=$SSH_CNT_PORT --label tsbridge.ssh.port=$SSH_CNT_PORT --label tsbridge.ssh.listen_addr=:$SSH_OUTPUT_PORT"
    
    # 7. Check container existence and handle based on mode
    CREATE_CONTAINER=false # Flag to decide if we run the container

    if [ "$(docker ps -aq -f name=^/${CONTAINER_NAME}$)" ]; then
        # Container exists
        if [ "$MODE" == "recreate" ]; then
            echo "Container $CONTAINER_NAME exists. Recreating as requested."
            if [ "$(docker ps -q -f name=^/${CONTAINER_NAME}$)" ]; then
                echo "Container is running. Stopping it."
                docker stop "$CONTAINER_NAME" > /dev/null
            fi
            echo "Removing existing container."
            docker rm "$CONTAINER_NAME" > /dev/null
            CREATE_CONTAINER=true # We removed it, so we must re-create it
        
        elif [ "$MODE" == "add" ]; then
            echo "Container $CONTAINER_NAME already exists. Skipping (mode: add)."
            CREATE_CONTAINER=false # Do not create
        fi
    else
        # Container does not exist
        echo "Container $CONTAINER_NAME does not exist. Creating..."
        CREATE_CONTAINER=true # We must create it
    fi

    # 8. Run the new container *if* flagged for creation
    if [ "$CREATE_CONTAINER" = true ]; then
        echo "Starting container '$CONTAINER_NAME' using image '$image_name'..."
        echo "Full command: docker run $DOCKER_OPTS $USER_VOLUME_OPT $VNC_OPT $NOVNC_OPT $SSH_OPT --label tsdproxy.name=dev-$username --name $CONTAINER_NAME $image_name"
        docker run $DOCKER_OPTS \
                $USER_VOLUME_OPT \
                $VNC_OPT \
                $NOVNC_OPT \
                $SSH_OPT \
                --label tsdproxy.name=dev-$username \
                --name "$CONTAINER_NAME" \
                "$image_name"

        echo "Full command: docker run $DOCKER_OPTS $USER_VOLUME_OPT $VNC_OPT $NOVNC_OPT $SSH_OPT --label tsdproxy.name=dev-$username --name $CONTAINER_NAME $image_name"

        echo "Successfully launched $CONTAINER_NAME"
    fi

    echo ""
    i=$((i + 1)) # Increment for the next line
done < "$INPUT_FILE"

echo "All containers have been processed."