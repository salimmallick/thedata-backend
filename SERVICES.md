# Services Status and Port Allocation

## Currently Running Services

### Database Services

#### ClickHouse
- Status: ✅ Running
- Ports:
  - 8123: HTTP Interface
  - 9001: Native Protocol (mapped from 9000)
- Health Check: `curl http://localhost:8123/`
- Credentials: 
  - User: ${CLICKHOUSE_USER}
  - Password: ${CLICKHOUSE_PASSWORD}

#### PostgreSQL
- Status: ✅ Running
- Ports:
  - 5432: PostgreSQL Protocol
- Health Check: `pg_isready -h localhost -p 5432`
- Credentials:
  - User: ${POSTGRES_USER}
  - Password: ${POSTGRES_PASSWORD}
  - Database: thedata

#### QuestDB
- Status: ✅ Running
- Ports:
  - 9000: Web Console
  - 8812: PostgreSQL Wire Protocol
  - 9003: Metrics
- Health Check: Web interface at http://localhost:9000
- Credentials:
  - User: ${QUESTDB_USER}
  - Password: ${QUESTDB_PASSWORD}

#### Materialize
- Status: 🟡 Not Started
- Ports:
  - 6875: PostgreSQL Protocol
- Dependencies:
  - Requires NATS
- Credentials:
  - User: materialize
  - Password: Not Set

### Message Brokers

#### NATS
- Status: ✅ Running
- Ports:
  - 4222: Client Port
  - 8222: Monitor Interface
- Health Check: `curl http://localhost:8222/healthz`
- Credentials:
  - System Password: ${SYSTEM_PASSWORD}
  - Admin Password: ${ADMIN_PASSWORD}
  - Client Password: ${CLIENT_PASSWORD}

#### Redis
- Status: 🟡 Not Started
- Ports:
  - 6379: Redis Protocol
- Health Check: `redis-cli ping`

### Monitoring & Metrics

#### Grafana
- Status: 🟡 Not Started
- Ports:
  - 3000: Web Interface
- Dependencies:
  - Requires QuestDB
  - Requires ClickHouse
- Credentials:
  - Admin Password: ${GRAFANA_ADMIN_PASSWORD}

#### Prometheus
- Status: 🟡 Not Started
- Ports:
  - 9090: Web Interface
- Health Check: `http://localhost:9090/-/healthy`

#### Alertmanager
- Status: 🟡 Not Started
- Ports:
  - 9093: Web Interface
- Health Check: `http://localhost:9093/-/healthy`

### Application Services

#### Dagster
- Status: 🟡 Not Started
- Ports:
  - 3001: Web Interface (mapped from 3000)
- Dependencies:
  - Requires PostgreSQL
  - Requires Materialize
  - Requires QuestDB
  - Requires ClickHouse
  - Requires Redis
- Health Check: `http://localhost:3001/health`

#### API
- Status: 🟡 Not Started
- Ports:
  - ${API_PORT}: HTTP Interface (mapped from 8000)
- Dependencies:
  - Requires NATS
- Health Check: `http://localhost:${API_PORT}/health`

### Reverse Proxy

#### Traefik
- Status: ✅ Running
- Ports:
  - 80: HTTP
  - 8080: Dashboard/API
  - 8082: Metrics
- Health Check: `http://localhost:8080/api/version`
- Dashboard: `http://localhost:8080/dashboard/#/`

## Port Allocation Summary

### Reserved Ports
- 80: Traefik HTTP
- 3000: Grafana
- 3001: Dagster
- 4222: NATS Client
- 5432: PostgreSQL
- 6379: Redis
- 6875: Materialize
- 8080: Traefik Dashboard
- 8082: Traefik Metrics
- 8123: ClickHouse HTTP
- 8222: NATS Monitor
- 8812: QuestDB PostgreSQL Protocol
- 9000: QuestDB Web Console
- 9001: ClickHouse Native Protocol
- 9003: QuestDB Metrics
- 9090: Prometheus
- 9093: Alertmanager
- ${API_PORT}: API Service

### Available Ports
The following port ranges are available for future services:
- 3002-3999 (excluding 3000-3001)
- 4000-4221
- 4223-5431
- 5433-6378
- 6380-6874
- 6876-8081
- 8084-8122
- 8124-8221
- 8223-8811
- 8813-8999
- 9002
- 9004-9089
- 9091-9092
- 9094-9999

## Network Configuration
- All services are connected to the `thedata_net` network
- Network is configured as external in docker-compose.yml 