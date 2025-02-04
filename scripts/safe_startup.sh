#!/bin/bash

set -e

# Configuration
LOG_FILE="logs/startup_$(date +%Y%m%d_%H%M%S).log"

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

wait_for_service() {
    local service=$1
    local max_attempts=${2:-30}
    local attempt=1
    
    log "Waiting for $service to be healthy..."
    while [ $attempt -le $max_attempts ]; do
        if docker-compose ps "$service" | grep -q "healthy"; then
            log "$service is healthy"
            return 0
        fi
        log "Attempt $attempt/$max_attempts: $service is not healthy yet, waiting..."
        sleep 5
        attempt=$((attempt+1))
    done
    
    error "$service failed to become healthy after $max_attempts attempts"
}

# Phase 1: Core Infrastructure
start_core_infrastructure() {
    log "Phase 1: Starting core infrastructure..."
    
    # Start Traefik
    log "Starting Traefik..."
    docker-compose up -d traefik
    wait_for_service traefik
    
    # Start NATS
    log "Starting NATS..."
    docker-compose up -d nats
    wait_for_service nats
    
    # Verify NATS streams
    if ! docker-compose exec -T nats nats stream ls >/dev/null 2>&1; then
        error "NATS streams verification failed"
    fi
    
    log "Core infrastructure started successfully"
}

# Phase 2: Storage Layer
start_storage_layer() {
    log "Phase 2: Starting storage layer..."
    
    # Start PostgreSQL
    log "Starting PostgreSQL..."
    docker-compose up -d postgres
    wait_for_service postgres
    
    # Start QuestDB
    log "Starting QuestDB..."
    docker-compose up -d questdb
    wait_for_service questdb
    
    # Start ClickHouse
    log "Starting ClickHouse..."
    docker-compose up -d clickhouse
    wait_for_service clickhouse
    
    # Verify database connections
    log "Verifying database connections..."
    
    # PostgreSQL check
    if ! docker-compose exec -T postgres pg_isready -U "$POSTGRES_USER"; then
        error "PostgreSQL connection check failed"
    fi
    
    # QuestDB check
    if ! curl -s "http://localhost:9000/health" | grep -q "OK"; then
        error "QuestDB health check failed"
    fi
    
    # ClickHouse check
    if ! docker-compose exec -T clickhouse clickhouse-client --query "SELECT 1"; then
        error "ClickHouse connection check failed"
    fi
    
    log "Storage layer started successfully"
}

# Phase 3: Processing Layer
start_processing_layer() {
    log "Phase 3: Starting processing layer..."
    
    # Start Materialize
    log "Starting Materialize..."
    docker-compose up -d materialize
    wait_for_service materialize
    
    # Verify Materialize connection
    if ! docker-compose exec -T materialize psql -h localhost -p 6875 -U materialize -c "SELECT version();" >/dev/null; then
        error "Materialize connection check failed"
    fi
    
    # Start Dagster
    log "Starting Dagster..."
    docker-compose up -d dagster dagster-daemon
    wait_for_service dagster
    wait_for_service dagster-daemon
    
    log "Processing layer started successfully"
}

# Phase 4: Monitoring Stack
start_monitoring_stack() {
    log "Phase 4: Starting monitoring stack..."
    
    # Start Prometheus
    log "Starting Prometheus..."
    docker-compose up -d prometheus
    wait_for_service prometheus
    
    # Start Alertmanager
    log "Starting Alertmanager..."
    docker-compose up -d alertmanager
    wait_for_service alertmanager
    
    # Start Grafana
    log "Starting Grafana..."
    docker-compose up -d grafana
    wait_for_service grafana
    
    # Verify monitoring endpoints
    if ! curl -s "http://localhost:9090/-/healthy" >/dev/null; then
        error "Prometheus health check failed"
    fi
    
    if ! curl -s "http://localhost:9093/-/healthy" >/dev/null; then
        error "Alertmanager health check failed"
    fi
    
    if ! curl -s "http://localhost:3000/api/health" >/dev/null; then
        error "Grafana health check failed"
    fi
    
    log "Monitoring stack started successfully"
}

# Phase 5: API Layer
start_api_layer() {
    log "Phase 5: Starting API layer..."
    
    # Start API service
    log "Starting API service..."
    docker-compose up -d api
    wait_for_service api
    
    # Verify API health
    if ! curl -s "http://localhost:${API_PORT}/health" >/dev/null; then
        error "API health check failed"
    fi
    
    log "API layer started successfully"
}

# Verify overall system health
verify_system_health() {
    log "Verifying overall system health..."
    
    # Check all services are running
    if docker-compose ps | grep -q "Exit"; then
        error "Some services have exited"
    fi
    
    # Check resource usage
    docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}"
    
    log "System health verification completed"
}

# Main startup procedure
main() {
    log "Starting phased system startup..."
    
    # Run system verification first
    log "Running system verification..."
    if ! ./scripts/verify_system.sh; then
        error "System verification failed"
    fi
    
    # Start each phase
    start_core_infrastructure
    start_storage_layer
    start_processing_layer
    start_monitoring_stack
    start_api_layer
    
    # Final health check
    verify_system_health
    
    log "All components started successfully!"
    log "System is ready at: http://localhost"
    
    # Print service endpoints
    cat << EOF

Service Endpoints:
-----------------
API: http://localhost:${API_PORT}
Grafana: http://localhost:3000
QuestDB: http://localhost:9000
Materialize: localhost:6875
ClickHouse: localhost:8123
Prometheus: http://localhost:9090
Alertmanager: http://localhost:9093
Dagster: http://localhost:3001

For detailed startup logs, see: $LOG_FILE
EOF
}

# Execute main function
main 