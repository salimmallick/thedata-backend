#!/bin/bash

# Exit on error
set -e

echo "Setting up theData.io platform..."

# Create necessary directories
mkdir -p config/{nats,questdb,clickhouse,dagster,materialize,traefik,grafana}/provisioning/dashboards

# Copy configurations
echo "Copying configurations..."
cp docker/docker-compose.yml docker-compose.yml
cp config/grafana/provisioning/dashboards/metrics.json config/grafana/provisioning/dashboards/

# Set up environment variables
echo "Setting up environment variables..."
cat > .env << EOL
# API Settings
API_PORT=8000
API_HOST=0.0.0.0

# Database Settings
CLICKHOUSE_USER=default
CLICKHOUSE_PASSWORD=
QUESTDB_USER=admin
QUESTDB_PASSWORD=quest

# Grafana Settings
GF_SECURITY_ADMIN_PASSWORD=thedata123
GF_INSTALL_PLUGINS=grafana-clickhouse-datasource,grafana-piechart-panel

# NATS Settings
NATS_USER=nats
NATS_PASSWORD=nats123
EOL

# Start services
echo "Starting services..."
docker-compose up -d

# Wait for services to be ready
echo "Waiting for services to be ready..."
sleep 10

# Check service health
echo "Checking service health..."
curl -f http://localhost:8000/health || echo "API not healthy"
curl -f http://localhost:3000/health || echo "Grafana not healthy"
curl -f http://localhost:9000/health || echo "QuestDB not healthy"
curl -f http://localhost:8123/ping || echo "ClickHouse not healthy"

echo "Setup complete! Access the services at:"
echo "- API: http://localhost:8000"
echo "- Grafana: http://localhost:3000"
echo "- QuestDB: http://localhost:9000"
echo "- ClickHouse: http://localhost:8123"
echo "- Dagster: http://localhost:3001" 