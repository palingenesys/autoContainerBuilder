# Auto Container Builder

This script creates Docker containers from different images and connects each container to a Tailscale network.

## Usage Guide

### User List

The `users.txt` file contains a list of users, one per line. Each row represents a user and their associated container. The first column is the username, and the second column is the Docker image name.

Run the script with `.\create-containers.sh add users.txt` to add the missing containers, use the `recreate` option to delete and recreate each container if existing.

### Docker Images

To build a Docker image from a Dockerfile, use the following command:

```sh
docker build -f Dockerfile.tag -t image-name:tag .
```

### Script Configuration

Container run options (except for ports), such as GPU support or volume mounts, can be specified in the `DOCKER_OPTS` variable.

Ports to be exposed through Tailscale must be defined in the `PORT_OPT` variable. For example, if you want to expose ports 5901 and 6080, set `PORT_OPT` accordingly. Update every occurrence as needed for your services.

## TSDProxy

### Configuration File

Edit the YAML file at `./tsdproxy/tsdproxy-conf` to add your Tailscale authentication key. Generate a key at [Tailscale Admin Console](https://login.tailscale.com/admin/settings/keys) (select "Reusable" and set the duration to 90 days).

### Proxy Container

From the `tsdproxy` directory, start the proxy container with:

```sh
docker compose up -d
```

After making configuration changes, restart the container. Tailscale nodes are automatically added when containers are created.

## Using `compose-containers.sh`

The `compose-containers.sh` script is designed to automate the creation and management of Docker containers for development environments. It supports connecting containers to a Tailscale network and forwarding ports for remote access.

### Prerequisites

1. **Input File**: Prepare a text file (e.g., `users.txt`) listing users and their associated Docker images. Each line should follow the format:
   ```
   username docker-image-name
   ```
   Lines starting with `#` are treated as comments and ignored.

2. **Tailscale Auth Key**: Obtain a valid Tailscale authentication key, it must be reusable.

### Script Usage

Run the script with the following syntax:
```sh
./compose-containers.sh <mode> <user_image_file.txt> <tailscale_auth_key>
```

- `<mode>`: Specify `add` to create new containers or `recreate` to delete and recreate existing containers.
- `<user_image_file.txt>`: Path to the input file containing user and image mappings.
- `<tailscale_auth_key>`: Your Tailscale authentication key.

### Example

To add containers for users listed in `users.txt`:
```sh
./compose-containers.sh add users.txt ts-auth-key
```

To recreate containers:
```sh
./compose-containers.sh recreate users.txt ts-auth-key
```

### What the Script Does

1. **Reads Input File**: Processes each user and their Docker image.
2. **Generates Docker Compose Configurations**: Creates a `docker-compose.yml` file for each user in the `deployments` directory.
3. **Launches Containers**: Starts the containers using Docker Compose.
4. **Port Forwarding**: Sets up port forwarding for SSH, VNC, and NoVNC access.

### Output

- Docker Compose configurations are stored in `deployments/<user_project_name>/docker-compose.yml`.
- A Tailscale Serve config is generated at `deployments/<user_project_name>/serve-config.json` to enable HTTPS for noVNC.
- Containers are launched with the following access details:
  - **SSH**: `ssh <container_name>`
  - **noVNC Access**: `https://<container_name>` (HTTPS via Tailscale Serve)

> **Note**: HTTPS certificates must be enabled in your Tailscale admin console under **DNS → HTTPS Certificates** at [https://login.tailscale.com/admin/dns](https://login.tailscale.com/admin/dns).