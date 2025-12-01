#!/bin/bash

# --- Configuration ---
CONTAINER_WORKSPACE_PATH="/workspace"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
COMPOSE_BASE_DIR="$SCRIPT_DIR/deployments"

DISPLAY_START_NUM=70

set -e

# 1. Check arguments
MODE="$1"
INPUT_FILE="$2"
TS_AUTHKEY="$3"

if [[ "$MODE" != "add" && "$MODE" != "recreate" && "$MODE" != "delete" ]]; then
  echo "Usage: $0 <mode> <user_image_file.txt> <tailscale_auth_key>" >&2
  echo "Error: Invalid mode '$MODE'. Mode must be 'add', 'recreate' or 'delete'." >&2
  exit 1
fi

if [[ -z "$INPUT_FILE" ]]; then
    echo "Error: You must provide a file listing users and their images." >&2
    exit 1
fi

if [[ "$MODE" != "delete" && -z "$TS_AUTHKEY" ]]; then
  echo "Error: You must provide a Tailscale Auth Key." >&2
  exit 1
fi

echo "--- Running in '$MODE' mode ---"

# 2. Read the input file
i=1
while read -r username image_name; do
    
    if [[ -z "$username" || "$username" == \#* ]]; then
        continue
    fi

    echo "--- Processing user: $username (Entry $i) ---"

    PROJECT_NAME="dev-$username"
    USER_DEPLOY_DIR="$COMPOSE_BASE_DIR/$PROJECT_NAME"
    HOST_VOLUME_PATH="$USER_DEPLOY_DIR/ws_$username"
    
    # Calculate display num (unique per container)
    DISPLAY_NUM=$((DISPLAY_START_NUM + i))

    mkdir -p "$HOST_VOLUME_PATH"
    mkdir -p "$USER_DEPLOY_DIR"

    # 3. Generate Docker Compose
    cat <<EOF > "$USER_DEPLOY_DIR/docker-compose.yml"
services:
  # -----------------------------------------------------------------
  # 1. Dev environment
  # Listens on specific high-numbered ports to avoid conflicts.
  # -----------------------------------------------------------------
  app:
    container_name: ${PROJECT_NAME}
    image: ${image_name}
    networks:
      default: 
      robot_lan:
        ipv4_address: 192.168.123.$((200 + i))
    hostname: ${PROJECT_NAME}
    environment:
      - USER=ubuntu
      - PASSWORD=ubuntu
      - NOVNC_WEB=/usr/lib/novnc
      - DISPLAY_NUM=${DISPLAY_NUM}
      - DISPLAY=:${DISPLAY_NUM}
      - ICEAUTHORITY=${CONTAINER_WORKSPACE_PATH}/.ICEauthority
      - XAUTHORITY=${CONTAINER_WORKSPACE_PATH}/.Xauthority
      - NVIDIA_VISIBLE_DEVICES=all
      - NVIDIA_DRIVER_CAPABILITIES=compute,utility,video,graphics,display
      - VK_ICD_FILENAMES=/etc/vulkan/icd.d/nvidia_icd.json
      - VNC_PORT=5901
      - NOVNC_PORT=6080
      - SSH_PORT=22
    volumes:
      - ${HOST_VOLUME_PATH}:${CONTAINER_WORKSPACE_PATH}
      - /etc/vulkan/icd.d:/etc/vulkan/icd.d:ro
      - /usr/share/vulkan/icd.d:/usr/share/vulkan/icd.d:ro
      - /tmp/.X11-unix:/tmp/.X11-unix:rw
      - /usr/local/nvidia/lib:/usr/local/nvidia/lib
      - /usr/local/nvidia/lib64:/usr/local/nvidia/lib64
    shm_size: '1gb'
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]
    restart: unless-stopped

  # -----------------------------------------------------------------
  # 2. Tailscale node
  # Runs in Bridge mode to get its own IP stack and Identity.
  # -----------------------------------------------------------------
  tailscale:
    container_name: ${PROJECT_NAME}-ts
    image: tailscale/tailscale:latest
    hostname: ${PROJECT_NAME}
    environment:
      - TS_AUTHKEY=${TS_AUTHKEY}
      - TS_HOSTNAME=${PROJECT_NAME}
      - TS_STATE_DIR=/var/lib/tailscale
      - TS_USERSPACE=false
      - TS_EXTRA_ARGS=--advertise-tags=tag:dev-envs
    volumes:
      - ts-state:/var/lib/tailscale
      - /dev/net/tun:/dev/net/tun
    cap_add:
      - NET_ADMIN
      - NET_RAW
    network_mode: service:app
    restart: unless-stopped

networks:
  robot_lan:
    external: true

volumes:
  ts-state:
EOF

    # 4. Execute Docker Compose or delete deployment
    echo "Generated config at $USER_DEPLOY_DIR/docker-compose.yml"
    cd "$USER_DEPLOY_DIR" || true

    if [ "$MODE" == "delete" ]; then
      if [ -f docker-compose.yml ]; then
        echo "Stopping and removing compose stack for $PROJECT_NAME..."
        docker compose down -v --remove-orphans || true
      else
        echo "No compose file found for $PROJECT_NAME, skipping docker compose down."
      fi
    else
      if [ "$MODE" == "recreate" ]; then
        docker compose up -d --force-recreate
      else
        docker compose up -d
      fi
      cd "$SCRIPT_DIR"

      echo "Launched: $PROJECT_NAME"
      echo "  -> SSH Access:   ssh $PROJECT_NAME"
      echo "  -> Web Access:   http://$PROJECT_NAME:6080"
      echo ""
    fi
    i=$((i + 1))

done < "$INPUT_FILE"

echo "All containers processed."