#!/bin/bash

# Exit on error
set -e

# Error handling
handle_error() {
    local exit_code=$?
    local line_number=$1
    echo "Error occurred in script at line: ${line_number}"
    echo "Exit code: ${exit_code}"
    cleanup_on_error
    exit "${exit_code}"
}

trap 'handle_error ${LINENO}' ERR

# Cleanup function
cleanup_on_error() {
    echo "Performing cleanup..."
    docker-compose down --volumes --remove-orphans
    rm -f .env.tmp
}

# Health check function
check_service_health() {
    local service=$1
    local max_attempts=${2:-60}
    local attempt=1
    
    echo "Checking health of $service..."
    while [ $attempt -le $max_attempts ]; do
        if docker-compose ps $service | grep -q "healthy"; then
            echo "$service is healthy"
            return 0
        fi
        echo "Attempt $attempt/$max_attempts: $service is not healthy yet, waiting..."
        sleep 5
        attempt=$((attempt+1))
    done
    
    echo "Error: $service failed to become healthy after $max_attempts attempts"
    return 1
}

echo "Initializing theData.io platform..."

# Check prerequisites
echo "Checking prerequisites..."
REQUIRED_COMMANDS=("docker" "docker-compose" "openssl" "curl")
for cmd in "${REQUIRED_COMMANDS[@]}"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Error: $cmd is required but not installed."
        exit 1
    fi
done

# Create directory structure with proper permissions
echo "Creating directory structure..."
for dir in config/{nats,questdb,clickhouse,dagster,materialize,traefik,grafana,prometheus}/{certs,provisioning/dashboards} data logs backups; do
    mkdir -p "$dir"
    chmod 755 "$dir"
done

# Generate SSL certificates with validation
echo "Generating SSL certificates..."
if ! ./scripts/generate_certs.sh; then
    echo "Certificate generation failed"
    exit 1
fi

# Set up environment with validation
echo "Setting up environment..."
if [ ! -f .env ]; then
    echo "Creating .env file from template..."
    cp .env.template .env.tmp
    
    # Generate secure random passwords
    RANDOM_STRING=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 32)
    sed -i "s/changeme123/$RANDOM_STRING/g" .env.tmp
    
    # Validate environment file
    while IFS='=' read -r key value; do
        if [ -z "$value" ]; then
            echo "Error: Empty value for $key in environment file"
            exit 1
        fi
    done < .env.tmp
    
    mv .env.tmp .env
fi

# Initialize data directories with proper permissions
echo "Initializing data directories..."
for dir in data/*; do
    if [ -d "$dir" ]; then
        chown -R 1000:1000 "$dir"
        chmod -R 755 "$dir"
    fi
done

# Pull Docker images with retry
echo "Pulling Docker images..."
max_attempts=3
attempt=1
while [ $attempt -le $max_attempts ]; do
    if docker-compose pull; then
        break
    fi
    echo "Attempt $attempt/$max_attempts: Pull failed, retrying..."
    sleep 5
    attempt=$((attempt+1))
done

if [ $attempt -gt $max_attempts ]; then
    echo "Error: Failed to pull Docker images after $max_attempts attempts"
    exit 1
fi

# Start core services with health checks
echo "Starting core services..."
docker-compose up -d nats postgres
check_service_health "nats" || exit 1
check_service_health "postgres" || exit 1

# Initialize databases with validation
echo "Initializing databases..."
docker-compose up -d clickhouse questdb
check_service_health "clickhouse" || exit 1
check_service_health "questdb" || exit 1

# Apply Materialize views with validation
echo "Applying Materialize views..."
docker-compose up -d materialize
check_service_health "materialize" || exit 1

# Apply views with error checking
if ! cat config/materialize/views.sql | docker-compose exec -T materialize materialized --command -; then
    echo "Error: Failed to apply Materialize views"
    exit 1
fi

# Start remaining services with health checks
echo "Starting remaining services..."
docker-compose up -d

# Verify all services
echo "Verifying all services..."
SERVICES=$(docker-compose ps --services)
for service in $SERVICES; do
    check_service_health "$service" || exit 1
done

# Initialize Grafana with retry
echo "Initializing Grafana..."
max_attempts=3
attempt=1
while [ $attempt -le $max_attempts ]; do
    if curl -X POST -H "Content-Type: application/json" \
         -d '{"name":"Main","orgId":1,"folder":"General","type":"file","disableDeletion":false,"updateIntervalSeconds":10,"allowUiUpdates":true}' \
         http://admin:${GRAFANA_ADMIN_PASSWORD}@localhost:3000/api/dashboards/db; then
        break
    fi
    echo "Attempt $attempt/$max_attempts: Grafana initialization failed, retrying..."
    sleep 5
    attempt=$((attempt+1))
done

if [ $attempt -gt $max_attempts ]; then
    echo "Error: Failed to initialize Grafana after $max_attempts attempts"
    exit 1
fi

# Verify monitoring setup
echo "Verifying monitoring setup..."
if ! docker-compose exec prometheus promtool check config /etc/prometheus/prometheus.yml; then
    echo "Error: Invalid Prometheus configuration"
    exit 1
fi

# Verify API health with retry
echo "Verifying API health..."
max_attempts=3
attempt=1
while [ $attempt -le $max_attempts ]; do
    if curl -f http://localhost:8000/health; then
        break
    fi
    echo "Attempt $attempt/$max_attempts: API health check failed, retrying..."
    sleep 5
    attempt=$((attempt+1))
done

if [ $attempt -gt $max_attempts ]; then
    echo "Error: API health check failed after $max_attempts attempts"
    exit 1
fi

# Set up backup schedule with validation
echo "Setting up backup schedule..."
BACKUP_CMD="/path/to/thedata/scripts/backup.sh"
if [ ! -f "$BACKUP_CMD" ]; then
    echo "Error: Backup script not found at $BACKUP_CMD"
    exit 1
fi

if ! (crontab -l 2>/dev/null; echo "0 0 * * * $BACKUP_CMD") | crontab -; then
    echo "Error: Failed to set up backup schedule"
    exit 1
fi

echo "Initialization complete! Services are available at:"
echo "- API: http://localhost:8000"
echo "- Grafana: http://localhost:3000"
echo "- QuestDB: http://localhost:9000"
echo "- ClickHouse: http://localhost:8123"
echo "- Dagster: http://localhost:3001"

# Print initial credentials with warning
echo -e "\nInitial Credentials (PLEASE CHANGE THESE IMMEDIATELY):"
echo "----------------------------------------"
echo "Grafana Admin Password: ${GRAFANA_ADMIN_PASSWORD}"
echo "ClickHouse User: ${CLICKHOUSE_USER}"
echo "QuestDB User: ${QUESTDB_USER}"
echo "----------------------------------------"

# Health summary with validation
echo -e "\nSystem Health Summary:"
if ! docker-compose ps; then
    echo "Error: Failed to get system health summary"
    exit 1
fi

# Resource usage check
echo -e "\nResource Usage:"
if ! docker stats --no-stream $(docker-compose ps -q); then
    echo "Error: Failed to get resource usage statistics"
    exit 1
fi

# Final validation
echo -e "\nPerforming final validation checks..."
for service in $SERVICES; do
    if ! docker-compose logs --tail=10 $service | grep -i "error"; then
        echo "$service: No recent errors found"
    else
        echo "Warning: Recent errors found in $service logs"
    fi
done

echo -e "\nSetup complete! Please change default passwords immediately."
echo "For security reasons, please run: ./scripts/change_default_passwords.sh" 