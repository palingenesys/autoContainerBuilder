#!/bin/bash

# --- Configuration ---
CONTAINER_WORKSPACE_PATH="/workspace"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
COMPOSE_BASE_DIR="$SCRIPT_DIR/deployments"

# Base ports on the HOST (Destination for the proxy)
VNC_START_PORT=10000
NOVNC_START_PORT=11000
SSH_START_PORT=12000

set -e

# 1. Check arguments
MODE="$1"
INPUT_FILE="$2"
TS_AUTHKEY="$3"

if [[ "$MODE" != "add" && "$MODE" != "recreate" ]]; then
    echo "Usage: $0 <mode> <user_image_file.txt> <tailscale_auth_key>" >&2
    echo "Error: Invalid mode '$MODE'. Mode must be 'add' or 'recreate'." >&2
    exit 1
fi

if [[ -z "$INPUT_FILE" ]]; then
    echo "Error: You must provide a file listing users and their images." >&2
    exit 1
fi

if [[ -z "$TS_AUTHKEY" ]]; then
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
    
    # Calculate Host Ports
    # The App container listens on these.
    VNC_PORT=$((VNC_START_PORT + i))
    NOVNC_PORT=$((NOVNC_START_PORT + i))
    SSH_PORT=$((SSH_START_PORT + i))

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
    network_mode: host
    environment:
      - USER=ubuntu
      - PASSWORD=ubuntu
      - NOVNC_WEB=/usr/lib/novnc
      - DISPLAY_NUM=70
      - NVIDIA_VISIBLE_DEVICES=all
      - NVIDIA_DRIVER_CAPABILITIES=compute,utility,video,graphics,display
      - DISPLAY=\${DISPLAY}
      - VK_ICD_FILENAMES=/etc/vulkan/icd.d/nvidia_icd.json
      - VNC_PORT=${VNC_PORT}
      - NOVNC_PORT=${NOVNC_PORT}
      - SSH_PORT=${SSH_PORT}
    volumes:
      - ${HOST_VOLUME_PATH}:${CONTAINER_WORKSPACE_PATH}
      - /etc/vulkan/icd.d:/etc/vulkan/icd.d:ro
      - /usr/share/vulkan/icd.d:/usr/share/vulkan/icd.d:ro
      - /tmp/.X11-unix:/tmp/.X11-unix:rw
      - /usr/local/nvidia/lib:/usr/local/nvidia/lib
      - /usr/local/nvidia/lib64:/usr/local/nvidia/lib64
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
    volumes:
      - ts-state:/var/lib/tailscale
      - /dev/net/tun:/dev/net/tun
    cap_add:
      - NET_ADMIN
      - NET_RAW
    # This allows the container to reach the HOST where the 'app' is running
    extra_hosts:
      - "host.docker.internal:host-gateway"
    restart: unless-stopped

  # -----------------------------------------------------------------
  # 3. Port forwarding
  # Sits inside the Tailscale network namespace.
  # Listens on standard ports (22, 6080) and tunnels to the Host ports.
  # -----------------------------------------------------------------
  forwarder:
    image: alpine/socat
    network_mode: service:tailscale
    depends_on:
      - tailscale
      - app
    deploy:
      restart_policy:
        condition: on-failure
    # Relay Logic:
    # Listen on Port 22 (Tailnet) -> Send to Host:${SSH_PORT}
    # Listen on Port 6080 (Tailnet) -> Send to Host:${NOVNC_PORT}
    entrypoint: ["/bin/sh", "-c"]
    command: 
      - |
        echo "Forwarding SSH:22 to Host:${SSH_PORT}..."
        echo "Forwarding NoVNC:6080 to Host:${NOVNC_PORT}..."
        socat TCP-LISTEN:22,fork,bind=0.0.0.0 TCP:host.docker.internal:${SSH_PORT} &
        socat TCP-LISTEN:6080,fork,bind=0.0.0.0 TCP:host.docker.internal:${NOVNC_PORT} &
        wait

volumes:
  ts-state:
EOF

    # 4. Execute Docker Compose
    echo "Generated config at $USER_DEPLOY_DIR/docker-compose.yml"
    cd "$USER_DEPLOY_DIR"

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
    i=$((i + 1))

done < "$INPUT_FILE"

echo "All containers processed."