#!/bin/bash

# Exit on error
set -e

# Configuration
BACKUP_DIR="/backups"
RETENTION_DAYS=7
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="backup_${DATE}.tar.gz"
LOG_FILE="/var/log/backup/backup.log"

# Initialize logging
mkdir -p "$(dirname "$LOG_FILE")"
exec 1> >(tee -a "$LOG_FILE")
exec 2>&1

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

error() {
    log "ERROR: $1"
    exit 1
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    command -v docker >/dev/null 2>&1 || error "Docker is required but not installed"
    command -v docker-compose >/dev/null 2>&1 || error "Docker Compose is required but not installed"
    
    # Check backup directory
    mkdir -p "$BACKUP_DIR" || error "Failed to create backup directory"
    
    # Check disk space
    AVAILABLE_SPACE=$(df -P "$BACKUP_DIR" | awk 'NR==2 {print $4}')
    MINIMUM_SPACE=$((10 * 1024 * 1024)) # 10GB in KB
    if [ "$AVAILABLE_SPACE" -lt "$MINIMUM_SPACE" ]; then
        error "Insufficient disk space for backup"
    fi
}

# Backup databases
backup_databases() {
    log "Starting database backups..."
    
    # QuestDB backup
    log "Backing up QuestDB..."
    docker-compose exec -T questdb questdb-backup \
        --directory /backup \
        --retention-days 7 || error "QuestDB backup failed"
    
    # ClickHouse backup
    log "Backing up ClickHouse..."
    docker-compose exec -T clickhouse clickhouse-client \
        --query "BACKUP DATABASE default TO '/backup/clickhouse_${DATE}'" || error "ClickHouse backup failed"
    
    # Materialize backup
    log "Backing up Materialize..."
    docker-compose exec -T materialize materialized \
        --command "BACKUP TO '/backup/materialize_${DATE}'" || error "Materialize backup failed"
    
    # Postgres backup
    log "Backing up Postgres..."
    docker-compose exec -T postgres pg_dumpall -U postgres > \
        "${BACKUP_DIR}/postgres_${DATE}.sql" || error "Postgres backup failed"
}

# Backup configurations
backup_configs() {
    log "Backing up configurations..."
    tar -czf "${BACKUP_DIR}/configs_${DATE}.tar.gz" \
        config/* || error "Configuration backup failed"
}

# Backup NATS data
backup_nats() {
    log "Backing up NATS data..."
    docker-compose exec -T nats nats-backup \
        --dir /backup \
        --name "nats_${DATE}" || error "NATS backup failed"
}

# Verify backups
verify_backups() {
    log "Verifying backups..."
    
    # Verify Postgres dump
    log "Verifying Postgres backup..."
    if ! pg_restore --list "${BACKUP_DIR}/postgres_${DATE}.sql" >/dev/null 2>&1; then
        error "Postgres backup verification failed"
    fi
    
    # Verify tar archives
    log "Verifying configuration backup..."
    if ! tar -tzf "${BACKUP_DIR}/configs_${DATE}.tar.gz" >/dev/null 2>&1; then
        error "Configuration backup verification failed"
    fi
    
    # Verify ClickHouse backup
    log "Verifying ClickHouse backup..."
    docker-compose exec -T clickhouse clickhouse-client \
        --query "CHECK BACKUP '/backup/clickhouse_${DATE}'" || error "ClickHouse backup verification failed"
}

# Cleanup old backups
cleanup_old_backups() {
    log "Cleaning up old backups..."
    find "$BACKUP_DIR" -type f -mtime +"$RETENTION_DAYS" -delete
    
    # Update backup metrics
    echo "backup_last_success_timestamp_seconds $(date +%s)" > /var/lib/node_exporter/backup_metrics.prom
}

# Upload to remote storage (if configured)
upload_to_remote() {
    if [ -n "$AWS_ACCESS_KEY_ID" ] && [ -n "$AWS_SECRET_ACCESS_KEY" ]; then
        log "Uploading to S3..."
        aws s3 cp "${BACKUP_DIR}/${BACKUP_FILE}" \
            "s3://${AWS_BUCKET}/${BACKUP_FILE}" || error "S3 upload failed"
    fi
}

# Main backup procedure
main() {
    log "Starting backup procedure..."
    
    # Check prerequisites
    check_prerequisites
    
    # Create temporary directory
    TEMP_DIR=$(mktemp -d)
    trap 'rm -rf "$TEMP_DIR"' EXIT
    
    # Perform backups
    backup_databases
    backup_configs
    backup_nats
    
    # Create consolidated backup
    tar -czf "${BACKUP_DIR}/${BACKUP_FILE}" -C "$TEMP_DIR" . || error "Failed to create consolidated backup"
    
    # Verify backups
    verify_backups
    
    # Upload to remote storage
    upload_to_remote
    
    # Cleanup old backups
    cleanup_old_backups
    
    log "Backup completed successfully"
}

# Run main procedure
main "$@" 