#!/bin/bash
set -xe
BASE_DIR="$HOME/test-dir"
if [ ! -d "$BASE_DIR" ]; then
    mkdir -p "$BASE_DIR"
fi
cd "$BASE_DIR"
function update_repo {
    local repo_name=$1
    local repo_url=$2
    if [ -d "$repo_name/.git" ]; then
        cd "$repo_name"
        git pull
        cd ..
    else
        git clone "$repo_url" "$repo_name"
    fi
}
update_repo "${FRONTEND_REPO}" "${FRONTEND_REPO_URL}"
update_repo "${BACKEND_REPO}" "${BACKEND_REPO_URL}"
cd ..
mapfile -t container_names < <(grep 'container_name:' docker-compose.yml | awk '{print $2}')
for container in "${container_names[@]}"; do
    latest_image="${container}:latest"
    if sudo docker ps -q -f name="$container" | grep -q .; then
        # Commit the running container to a backup image
        sudo docker commit "$container" "${USER}_${container}:backup"
        echo "Backup image for $container created as $backup_image"
    else
        echo "No running container found for $container, skipping backup."
    fi
    sudo docker container rm -f "$container"
    echo "$container removed"
    sudo docker-compose up --no-start
    sudo docker-compose build "$container"
    sudo docker-compose up -d "$container"
    echo "$container attempted to start."
    sleep 5  # Allow some time for the container to start or fail.
    if ! sudo docker ps -q -f name="$container" | grep -q .; then
        echo "Failure detected, reverting to backup image for $container."
        sudo docker tag "${USER}_${container}:backup" "${USER}_${container}:latest"
        sudo docker-compose up -d "$container"
        if sudo docker ps -q -f name="$container" | grep -q .; then
            echo "$container started successfully with backup image."
        else
            echo "Failed to start $container even after reverting to backup."
        fi
    else
        echo "$container is running successfully."
    fi
done
sudo docker rmi $(sudo docker images -f "dangling=true" -q)
