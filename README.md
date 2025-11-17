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