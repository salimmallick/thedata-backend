#!/bin/bash

# Exit on error
set -e

echo "Running health checks for TheData Platform..."

# Function to check service health
check_service() {
    local service=$1
    local port=$2
    local endpoint=${3:-/}
    local expected_code=${4:-200}
    
    echo -n "Checking $service (port $port)... "
    if curl -s -o /dev/null -w "%{http_code}" localhost:$port$endpoint | grep -q $expected_code; then
        echo "OK"
        return 0
    else
        echo "FAILED"
        return 1
    fi
}

# Function to check database connection
check_db() {
    local service=$1
    local port=$2
    echo -n "Checking $service (port $port)... "
    if nc -z localhost $port; then
        echo "OK"
        return 0
    else
        echo "FAILED"
        return 1
    fi
}

# Check Docker services status
echo "Checking Docker services..."
docker compose ps

# Check individual services
echo -e "\nChecking service endpoints..."

# Web Services
check_service "API" "8000" "/health"
check_service "Dagster" "3001" "/health"
check_service "Grafana" "3000" "/api/health"
check_service "QuestDB Web Console" "9000"
check_service "Prometheus" "9090" "/-/healthy"
check_service "Alertmanager" "9093" "/-/healthy"
check_service "Traefik Dashboard" "8080" "/api/version"

# Database Connections
check_db "PostgreSQL" "5432"
check_db "QuestDB" "8812"
check_db "ClickHouse" "9001"
check_db "Redis" "6379"
check_db "NATS" "4222"
check_db "Materialize" "6875"

# Check logs for errors
echo -e "\nChecking recent logs for errors..."
docker compose logs --tail=50 | grep -i "error" || echo "No recent errors found"

# Resource usage
echo -e "\nResource Usage:"
docker stats --no-stream $(docker compose ps -q)

echo -e "\nHealth check complete!" 