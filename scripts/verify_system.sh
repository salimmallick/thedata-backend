#!/bin/bash

set -e

# Configuration
LOG_FILE="logs/verify.log"

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

# Check configuration files
verify_configs() {
    log "Verifying configuration files..."
    
    # Required config files
    required_configs=(
        "config/nats/jetstream.conf"
        "config/questdb/server.conf"
        "config/clickhouse/config.xml"
        "config/prometheus/prometheus.yml"
        "config/prometheus/rules/alerts.yml"
        "config/grafana/provisioning/datasources/datasources.yml"
        "config/grafana/provisioning/dashboards/system-overview.json"
        "config/traefik/traefik.yml"
        "config/traefik/dynamic/middleware.yml"
        ".env"
    )
    
    for config in "${required_configs[@]}"; do
        [ -f "$config" ] || error "Missing required config: $config"
        
        # Verify file permissions
        if [[ "$config" == *"certs"* ]] || [[ "$config" == *.env ]]; then
            [[ $(stat -f "%OLp" "$config") == "600" ]] || error "Incorrect permissions on sensitive file: $config"
        else
            [[ $(stat -f "%OLp" "$config") == "644" ]] || error "Incorrect permissions on config file: $config"
        fi
    done
}

# Verify environment variables
verify_env() {
    log "Verifying environment variables..."
    
    required_vars=(
        "API_PORT"
        "API_HOST"
        "CLICKHOUSE_USER"
        "CLICKHOUSE_PASSWORD"
        "QUESTDB_USER"
        "QUESTDB_PASSWORD"
        "POSTGRES_USER"
        "POSTGRES_PASSWORD"
        "GRAFANA_ADMIN_PASSWORD"
        "NATS_AUTH_TOKEN"
        "SSL_EMAIL"
        "DAGSTER_CELERY_BROKER_URL"
        "DAGSTER_CELERY_RESULT_BACKEND"
    )
    
    # Source environment file
    if [ ! -f .env ]; then
        error ".env file not found"
    fi
    
    # Export variables
    while IFS='=' read -r key value; do
        if [[ ! $key =~ ^# && -n $key ]]; then
            export "$key=$value"
        fi
    done < .env
    
    for var in "${required_vars[@]}"; do
        if [ -z "${!var}" ]; then
            error "Required environment variable not set: $var"
        fi
    done
    
    log "Environment variables verified successfully"
}

# Verify system resources
verify_resources() {
    log "Verifying system resources..."
    
    # Check CPU cores
    CPU_CORES=$(sysctl -n hw.ncpu)
    [ "$CPU_CORES" -lt 4 ] && error "Insufficient CPU cores. Minimum 4 required, found: $CPU_CORES"
    
    # Check memory (in GB)
    TOTAL_MEM=$(($(sysctl -n hw.memsize) / 1024 / 1024 / 1024))
    [ "$TOTAL_MEM" -lt 16 ] && error "Insufficient memory. Minimum 16GB required, found: ${TOTAL_MEM}GB"
    
    # Check disk space (in GB)
    AVAILABLE_SPACE=$(($(df -k . | awk 'NR==2 {print $4}') / 1024 / 1024))
    [ "$AVAILABLE_SPACE" -lt 100 ] && error "Insufficient disk space. Minimum 100GB required, found: ${AVAILABLE_SPACE}GB"
    
    # Check open files limit
    ULIMIT=$(ulimit -n)
    [ "$ULIMIT" -lt 65536 ] && error "Insufficient file descriptors. Minimum 65536 required, found: $ULIMIT"
    
    log "System resources verified successfully"
}

# Verify network configuration
verify_network() {
    log "Verifying network configuration..."
    
    # Check required ports are available
    required_ports=(80 443 4222 8222 6875 9000 8812 8123 9090 9093 3000 5432)
    
    for port in "${required_ports[@]}"; do
        if nc -z localhost "$port" 2>/dev/null; then
            error "Port $port is already in use"
        fi
    done
    
    # Check Docker network
    if ! docker network ls | grep -q "thedata_net"; then
        log "Creating Docker network 'thedata_net'..."
        if ! docker network create --driver bridge thedata_net; then
            log "Failed to create network with default subnet, trying alternative subnet..."
            if ! docker network create --driver bridge --subnet 172.29.0.0/16 thedata_net; then
                error "Failed to create Docker network 'thedata_net'"
            fi
        fi
    fi
    
    log "Network configuration verified successfully"
}

# Verify certificates
verify_certificates() {
    log "Verifying certificates..."
    
    cert_dir="config/nats/certs"
    [ -d "$cert_dir" ] || error "Certificate directory not found: $cert_dir"
    
    required_certs=(
        "ca.pem"
        "server-cert.pem"
        "server-key.pem"
    )
    
    for cert in "${required_certs[@]}"; do
        [ -f "$cert_dir/$cert" ] || error "Missing certificate: $cert_dir/$cert"
        
        # Verify certificate permissions
        [[ $(stat -f "%OLp" "$cert_dir/$cert") == "600" ]] || error "Incorrect permissions on certificate: $cert_dir/$cert"
        
        # Verify certificate validity
        if [[ "$cert" == *"cert.pem" ]]; then
            openssl x509 -in "$cert_dir/$cert" -noout -checkend 2592000 || error "Certificate will expire within 30 days: $cert"
        fi
    done
}

# Verify Docker configuration
verify_docker() {
    log "Verifying Docker configuration..."
    
    # Check Docker daemon
    if ! docker info >/dev/null 2>&1; then
        error "Docker daemon is not running"
    fi
    log "Docker daemon is running"
    
    # Check Docker Compose
    if ! docker-compose version >/dev/null 2>&1; then
        error "Docker Compose not installed"
    fi
    log "Docker Compose is installed"
    
    # Verify images exist
    log "Verifying Docker images..."
    required_images=(
        "nats:2.10.5"
        "materialize/materialized:v0.91.0"
        "questdb/questdb:7.3.7"
        "clickhouse/clickhouse-server:23.8.8.20"
        "grafana/grafana:10.2.3"
        "prom/prometheus:v2.48.1"
        "prom/alertmanager:v0.26.0"
        "postgres:15.5"
        "traefik:v2.10.7"
    )
    
    for image in "${required_images[@]}"; do
        log "Pulling image: $image"
        if ! docker pull "$image" >/dev/null; then
            error "Failed to pull Docker image: $image"
        fi
    done
    
    log "Docker configuration verified successfully"
}

# Verify Dagster configuration
verify_dagster() {
    log "Verifying Dagster configuration..."
    
    # Check Dagster workspace
    if [ ! -f "config/dagster/workspace.yaml" ]; then
        error "Dagster workspace configuration not found"
    fi
    
    # Check Dagster repository
    if [ ! -f "app/dagster/repository.py" ]; then
        error "Dagster repository not found"
    fi
    
    # Check Dagster Dockerfile
    if [ ! -f "Dockerfile.dagster" ]; then
        error "Dagster Dockerfile not found"
    fi
    
    # Check Dagster directories
    required_dirs=(
        "data/dagster"
        "logs/dagster"
        "config/dagster"
        "app/dagster"
    )
    
    for dir in "${required_dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            error "Required Dagster directory not found: $dir"
        fi
    done
    
    log "Dagster configuration verified successfully"
}

# Verify data directories
verify_data_dirs() {
    log "Verifying data directories..."
    
    required_dirs=(
        "data/postgres"
        "data/questdb"
        "data/clickhouse"
        "data/materialize"
        "data/nats"
        "logs"
        "backups"
    )
    
    for dir in "${required_dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            log "Creating directory: $dir"
            mkdir -p "$dir"
        fi
        
        # Verify permissions
        [[ $(stat -f "%OLp" "$dir") =~ ^7[0-7][0-7]$ ]] || error "Incorrect permissions on directory: $dir"
    done
    
    log "Data directories verified successfully"
}

# Verify backup configuration
verify_backup() {
    log "Verifying backup configuration..."
    
    # Check backup script
    if [ ! -f "scripts/backup.sh" ]; then
        error "Backup script not found"
    fi
    
    # Check backup directory permissions
    if [ ! -d "backups" ]; then
        error "Backup directory not found"
    fi
    
    [[ $(stat -f "%OLp" "backups") == "700" ]] || error "Incorrect permissions on backup directory"
    
    log "Backup configuration verified successfully"
}

# Main verification procedure
main() {
    log "Starting system verification..."
    
    verify_configs
    verify_env
    verify_resources
    verify_network
    verify_certificates
    verify_docker
    verify_dagster
    verify_data_dirs
    verify_backup
    
    log "All system verifications completed successfully!"
}

# Execute main function
main 