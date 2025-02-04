#!/bin/bash

# Exit on error
set -e

echo "Initializing TheData Platform..."

# Create required directories
mkdir -p data/{questdb,clickhouse,postgres,redis,nats,materialize,prometheus,alertmanager,grafana,dagster}
mkdir -p logs/{questdb,clickhouse,postgres,redis,nats,materialize,prometheus,alertmanager,grafana,dagster,api}
mkdir -p backups

# Set permissions
chmod -R 755 data logs backups

# Check if .env exists
if [ ! -f .env ]; then
    echo "Creating .env file from example..."
    cp .env.example .env
    echo "Please edit .env with your configurations"
fi

# Create network if it doesn't exist
if ! docker network inspect thedata_net >/dev/null 2>&1; then
    echo "Creating Docker network: thedata_net"
    docker network create thedata_net
fi

echo "Initialization complete!"
echo "Next steps:"
echo "1. Edit .env with your configurations"
echo "2. Run 'docker compose up -d' to start the platform"
echo "3. Run './scripts/health_check.sh' to verify the setup" 