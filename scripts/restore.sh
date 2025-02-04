#!/bin/bash

# Exit on error
set -e

# Check if backup file is provided
if [ -z "$1" ]; then
    echo "Error: No backup file specified"
    echo "Usage: $0 <backup_file.tar.gz>"
    exit 1
fi

BACKUP_FILE="$1"
RESTORE_DIR="./restore_temp"
BACKUP_NAME=$(basename "$BACKUP_FILE" .tar.gz)

echo "Starting restore of TheData Platform..."

# Create temporary restore directory
rm -rf "${RESTORE_DIR}"
mkdir -p "${RESTORE_DIR}"

# Extract backup archive
echo "Extracting backup archive..."
tar -xzf "${BACKUP_FILE}" -C "${RESTORE_DIR}"

# Stop all services
echo "Stopping all services..."
docker compose down

# Restore configuration files
echo "Restoring configuration files..."
cp -r "${RESTORE_DIR}/${BACKUP_NAME}/config"/* config/

# Restore environment variables
echo "Restoring environment variables..."
cp "${RESTORE_DIR}/${BACKUP_NAME}/.env" .env

# Restore databases
echo "Restoring databases..."

# Start required services
docker compose up -d postgres questdb clickhouse

# Wait for services to be ready
echo "Waiting for services to be ready..."
sleep 30

# PostgreSQL
echo "Restoring PostgreSQL..."
docker compose exec -T postgres psql -U "${POSTGRES_USER}" thedata < "${RESTORE_DIR}/${BACKUP_NAME}/postgres_dump.sql"

# QuestDB
echo "Restoring QuestDB data..."
docker compose stop questdb
rm -rf data/questdb/*
tar -xzf "${RESTORE_DIR}/${BACKUP_NAME}/questdb_data.tar.gz" -C data/
docker compose start questdb

# ClickHouse
echo "Restoring ClickHouse..."
docker compose exec -T clickhouse clickhouse-client --query="RESTORE TABLE * FROM '${RESTORE_DIR}/${BACKUP_NAME}/clickhouse_backup'"

# Start remaining services
echo "Starting remaining services..."
docker compose up -d

# Restore Materialize views
echo "Restoring Materialize views..."
docker compose exec -T materialize psql -h localhost -p 6875 -U materialize < "${RESTORE_DIR}/${BACKUP_NAME}/materialize_views.sql"

# Restore Grafana dashboards
echo "Restoring Grafana dashboards..."
cp -r "${RESTORE_DIR}/${BACKUP_NAME}/grafana_dashboards"/* config/grafana/provisioning/dashboards/

# Restore Prometheus configuration
echo "Restoring Prometheus configuration..."
cp -r "${RESTORE_DIR}/${BACKUP_NAME}/prometheus_config"/* config/prometheus/

# Cleanup
echo "Cleaning up temporary files..."
rm -rf "${RESTORE_DIR}"

# Verify services
echo "Verifying services..."
./scripts/healthcheck.sh

echo "Restore complete! Please verify that all services are running correctly."
echo "Note: You may need to restart some services if they're not functioning properly." 