#!/bin/bash

set -e

# Configuration
BACKUP_DIR="backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="logs/backup_${TIMESTAMP}.log"

# Initialize logging
mkdir -p "$(dirname "$LOG_FILE")"
exec 1> >(tee -a "$LOG_FILE")
exec 2>&1

# Utility functions
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

error() {
    log "ERROR: $1"
    exit 1
}

# Create backup directory structure
create_backup_dirs() {
    log "Creating backup directory structure..."
    
    mkdir -p "${BACKUP_DIR}/${TIMESTAMP}"/{postgres,questdb,clickhouse,materialize,nats,config}
    chmod -R 700 "${BACKUP_DIR}/${TIMESTAMP}"
}

# Backup PostgreSQL databases
backup_postgres() {
    log "Backing up PostgreSQL databases..."
    
    docker-compose exec -T postgres pg_dumpall -U "$POSTGRES_USER" > \
        "${BACKUP_DIR}/${TIMESTAMP}/postgres/full_backup.sql"
    
    # Compress backup
    gzip "${BACKUP_DIR}/${TIMESTAMP}/postgres/full_backup.sql"
}

# Backup QuestDB data
backup_questdb() {
    log "Backing up QuestDB data..."
    
    # Stop QuestDB to ensure data consistency
    docker-compose stop questdb
    
    # Backup data directory
    tar -czf "${BACKUP_DIR}/${TIMESTAMP}/questdb/data_backup.tar.gz" data/questdb/
    
    # Restart QuestDB
    docker-compose start questdb
}

# Backup ClickHouse data
backup_clickhouse() {
    log "Backing up ClickHouse data..."
    
    # Get list of databases
    databases=$(docker-compose exec -T clickhouse clickhouse-client --query "SHOW DATABASES")
    
    for db in $databases; do
        if [[ "$db" != "system" && "$db" != "information_schema" && "$db" != "INFORMATION_SCHEMA" ]]; then
            log "Backing up database: $db"
            docker-compose exec -T clickhouse clickhouse-client --query "BACKUP DATABASE $db TO Disk('backups', '${TIMESTAMP}/${db}')"
        fi
    done
}

# Backup Materialize views and sources
backup_materialize() {
    log "Backing up Materialize metadata..."
    
    # Backup views
    docker-compose exec -T materialize psql -h localhost -p 6875 -U materialize \
        -c "\dx" > "${BACKUP_DIR}/${TIMESTAMP}/materialize/views.sql"
    
    # Backup sources
    docker-compose exec -T materialize psql -h localhost -p 6875 -U materialize \
        -c "SELECT * FROM mz_sources" > "${BACKUP_DIR}/${TIMESTAMP}/materialize/sources.sql"
}

# Backup NATS streams
backup_nats() {
    log "Backing up NATS streams..."
    
    # Get list of streams
    streams=$(docker-compose exec -T nats nats stream ls --json | jq -r '.streams[].name')
    
    for stream in $streams; do
        log "Backing up stream: $stream"
        docker-compose exec -T nats nats stream backup "$stream" \
            "${BACKUP_DIR}/${TIMESTAMP}/nats/${stream}.backup"
    done
}

# Backup configuration files
backup_config() {
    log "Backing up configuration files..."
    
    # Backup all config files
    tar -czf "${BACKUP_DIR}/${TIMESTAMP}/config/config_backup.tar.gz" config/
    
    # Backup environment files
    cp .env "${BACKUP_DIR}/${TIMESTAMP}/config/.env.backup"
    cp .env.template "${BACKUP_DIR}/${TIMESTAMP}/config/.env.template.backup"
}

# Cleanup old backups
cleanup_old_backups() {
    log "Cleaning up old backups..."
    
    # Keep last 7 daily backups
    find "$BACKUP_DIR" -maxdepth 1 -type d -mtime +7 -exec rm -rf {} \;
}

# Verify backup integrity
verify_backup() {
    log "Verifying backup integrity..."
    
    # Check if all expected files exist
    required_files=(
        "postgres/full_backup.sql.gz"
        "questdb/data_backup.tar.gz"
        "materialize/views.sql"
        "materialize/sources.sql"
        "config/config_backup.tar.gz"
        "config/.env.backup"
    )
    
    for file in "${required_files[@]}"; do
        if [ ! -f "${BACKUP_DIR}/${TIMESTAMP}/${file}" ]; then
            error "Missing backup file: ${file}"
        fi
    done
    
    # Check file sizes
    find "${BACKUP_DIR}/${TIMESTAMP}" -type f -size 0 -exec error "Empty backup file: {}" \;
    
    log "Backup verification completed successfully"
}

# Main backup procedure
main() {
    log "Starting backup procedure..."
    
    create_backup_dirs
    backup_config
    backup_postgres
    backup_questdb
    backup_clickhouse
    backup_materialize
    backup_nats
    verify_backup
    cleanup_old_backups
    
    log "Backup completed successfully at ${BACKUP_DIR}/${TIMESTAMP}"
    
    # Create symlink to latest backup
    ln -sf "${BACKUP_DIR}/${TIMESTAMP}" "${BACKUP_DIR}/latest"
}

# Execute main function
main 