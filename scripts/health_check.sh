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
    local is_critical="${5:-true}"
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
    if [ "$is_critical" = true ]; then
        docker compose logs "$service" --tail 20
        return 1
    else
        echo "Warning: Non-critical service $service is not available"
        return 0
    fi
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
    local is_critical="${2:-true}"
    if ! docker compose ps "$service" --format json | grep -q "running"; then
        echo "Error: Service $service is not running"
        if [ "$is_critical" = true ]; then
            echo "Service logs:"
            docker compose logs "$service" --tail 50
            return 1
        else
            echo "Warning: Non-critical service $service is not running"
            return 0
        fi
    fi
    return 0
}

# Check individual services
echo -e "\nChecking service endpoints..."

# Check core services first (these are critical)
check_service_health "nats" true || exit 1
check_service_health "postgres" true || exit 1
check_service_health "redis" true || exit 1

# Web Services - Core (these are critical)
check_service "API" "8000" "/health" "200" true || exit 1
check_service "Dagster" "3001" "/health" "200" true || exit 1
check_service "QuestDB Web Console" "9000" "/" "200" true || exit 1

# Monitoring Services (these are non-critical)
echo -e "\nChecking monitoring services (non-critical)..."
check_service "Grafana" "3000" "/api/health" "200" false
check_service "Prometheus" "9090" "/-/healthy" "200" false
check_service "Alertmanager" "9093" "/-/healthy" "200" false

# Infrastructure Services (these are critical)
check_service "Traefik Dashboard" "8080" "/api/version" "200" true || exit 1

# Database Connections (these are critical)
check_db "PostgreSQL" "5432" || exit 1
check_db "QuestDB" "8812" || exit 1
check_db "ClickHouse" "9001" || exit 1
check_db "Redis" "6379" || exit 1
check_db "NATS" "4222" || exit 1
check_db "Materialize" "6875" || exit 1

# Check logs for errors (excluding monitoring services)
echo -e "\nChecking recent logs for errors..."
docker compose logs --tail=50 api dagster postgres questdb clickhouse redis nats materialize traefik | grep -i "error" || echo "No recent errors found in core services"

# Resource usage (ignore errors)
echo -e "\nResource Usage:"
docker stats --no-stream "$(docker compose ps -q)" 2>/dev/null || true

echo -e "\nHealth check complete!"

# Only check for critical service failures
failed_services=$(docker compose ps api dagster postgres questdb clickhouse redis nats materialize traefik --format json | grep -c "Exit" || echo "0")
if [ "$failed_services" -gt 0 ]; then
    echo "Error: $failed_services critical service(s) have failed to start"
    exit 1
fi 