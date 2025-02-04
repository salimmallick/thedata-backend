#!/bin/bash

# Exit on error
set -e

echo "Running health checks for TheData Platform..."

# Function to check service health with retries
check_service() {
    local service="$1"
    local port="$2"
    local endpoint="${3:-/}"
    local expected_code="${4:-200}"
    local max_retries=5
    local retry_count=0
    local wait_time=10
    
    echo -n "Checking $service (port $port)... "
    while [ $retry_count -lt $max_retries ]; do
        if curl -s -o /dev/null -w "%{http_code}" "localhost:${port}${endpoint}" | grep -q "${expected_code}"; then
            echo "OK"
            return 0
        fi
        retry_count=$((retry_count + 1))
        if [ $retry_count -lt $max_retries ]; then
            echo -n "retrying ($retry_count/$max_retries)... "
            sleep $wait_time
        fi
    done
    echo "FAILED"
    echo "Error: Could not connect to $service on port $port after $max_retries attempts"
    docker compose logs "$service" --tail 20
    return 1
}

# Function to check database connection with retries
check_db() {
    local service="$1"
    local port="$2"
    local max_retries=5
    local retry_count=0
    local wait_time=10
    
    echo -n "Checking $service (port $port)... "
    while [ $retry_count -lt $max_retries ]; do
        if nc -z localhost "${port}"; then
            echo "OK"
            return 0
        fi
        retry_count=$((retry_count + 1))
        if [ $retry_count -lt $max_retries ]; then
            echo -n "retrying ($retry_count/$max_retries)... "
            sleep $wait_time
        fi
    done
    echo "FAILED"
    echo "Error: Could not connect to $service on port $port after $max_retries attempts"
    docker compose logs "$service" --tail 20
    return 1
}

# Initial wait for services to start
echo "Waiting for services to initialize (60s)..."
sleep 60

# Check Docker services status
echo "Checking Docker services..."
docker compose ps

# Function to check if service is running and healthy
check_service_health() {
    local service="$1"
    if ! docker compose ps "$service" --format json | grep -q "running"; then
        echo "Error: Service $service is not running"
        echo "Service logs:"
        docker compose logs "$service" --tail 50
        return 1
    fi
    return 0
}

# Check individual services
echo -e "\nChecking service endpoints..."

# Check core services first
check_service_health "nats" || true
check_service_health "postgres" || true
check_service_health "redis" || true

# Web Services
check_service "API" "8000" "/health" || true
check_service "Dagster" "3001" "/health" || true
check_service "Grafana" "3000" "/api/health" || true
check_service "QuestDB Web Console" "9000" || true
check_service "Prometheus" "9090" "/-/healthy" || true
check_service "Alertmanager" "9093" "/-/healthy" || true
check_service "Traefik Dashboard" "8080" "/api/version" || true

# Database Connections
check_db "PostgreSQL" "5432" || true
check_db "QuestDB" "8812" || true
check_db "ClickHouse" "9001" || true
check_db "Redis" "6379" || true
check_db "NATS" "4222" || true
check_db "Materialize" "6875" || true

# Check logs for errors
echo -e "\nChecking recent logs for errors..."
docker compose logs --tail=50 | grep -i "error" || echo "No recent errors found"

# Resource usage
echo -e "\nResource Usage:"
docker stats --no-stream "$(docker compose ps -q)" || true

echo -e "\nHealth check complete!"

# If any service failed, exit with error
failed_services=$(docker compose ps --format json | grep -c "Exit")
if [ "$failed_services" -gt 0 ]; then
    echo "Error: $failed_services service(s) have failed to start"
    exit 1
fi 