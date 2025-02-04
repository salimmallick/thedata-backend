#!/bin/bash

# Exit on error
set -e

# Configuration
BACKUP_DIR="./backups"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_PATH="${BACKUP_DIR}/${DATE}"

echo "Starting backup of TheData Platform..."

# Create backup directory
mkdir -p "${BACKUP_PATH}"

# Backup configuration files
echo "Backing up configuration files..."
cp -r config "${BACKUP_PATH}/config"

# Backup environment variables
echo "Backing up environment variables..."
cp .env "${BACKUP_PATH}/.env"

# Backup databases
echo "Backing up databases..."

# PostgreSQL
echo "Backing up PostgreSQL..."
docker compose exec -T postgres pg_dump -U "${POSTGRES_USER}" thedata > "${BACKUP_PATH}/postgres_dump.sql"

# QuestDB
echo "Backing up QuestDB data..."
tar -czf "${BACKUP_PATH}/questdb_data.tar.gz" data/questdb

# ClickHouse
echo "Backing up ClickHouse..."
docker compose exec -T clickhouse clickhouse-client --query="BACKUP TABLE * TO '${BACKUP_PATH}/clickhouse_backup'"

# Materialize
echo "Backing up Materialize views..."
cp config/materialize/views.sql "${BACKUP_PATH}/materialize_views.sql"

# Backup Grafana dashboards
echo "Backing up Grafana dashboards..."
cp -r config/grafana/provisioning/dashboards "${BACKUP_PATH}/grafana_dashboards"

# Backup Prometheus data
echo "Backing up Prometheus configuration..."
cp -r config/prometheus "${BACKUP_PATH}/prometheus_config"

# Create archive
echo "Creating backup archive..."
cd "${BACKUP_DIR}"
tar -czf "${DATE}.tar.gz" "${DATE}"
rm -rf "${DATE}"

# Cleanup old backups (keep last 7 days)
find "${BACKUP_DIR}" -name "*.tar.gz" -mtime +7 -delete

echo "Backup complete! Archive created at: ${BACKUP_DIR}/${DATE}.tar.gz"
echo "Note: Old backups (>7 days) have been cleaned up." 