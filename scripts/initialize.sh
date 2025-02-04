#!/bin/bash

# Exit on error
set -e

echo "Initializing TheData Platform directories..."

# Create required directories
directories=(
    "data/postgres"
    "data/questdb"
    "data/clickhouse"
    "data/materialize"
    "data/nats"
    "data/grafana"
    "data/prometheus"
    "data/alertmanager"
    "data/dagster"
    "data/redis"
    "logs/api"
    "logs/nats"
    "logs/postgres"
    "logs/questdb"
    "logs/clickhouse"
    "logs/materialize"
    "logs/grafana"
    "logs/dagster"
    "logs/redis"
    "backups"
)

for dir in "${directories[@]}"; do
    echo "Creating directory: $dir"
    mkdir -p "$dir"
    chmod 755 "$dir"
done

# Create Docker network if it doesn't exist
if ! docker network ls | grep -q "thedata_net"; then
    echo "Creating Docker network: thedata_net"
    docker network create --driver bridge thedata_net || {
        echo "Failed to create network with default subnet, trying alternative subnet..."
        docker network create --driver bridge --subnet 172.29.0.0/16 thedata_net
    }
fi

echo "Initialization complete!"
echo "Next steps:"
echo "1. Edit .env with your configurations"
echo "2. Run 'docker compose up -d' to start the platform"
echo "3. Run './scripts/health_check.sh' to verify the setup" 