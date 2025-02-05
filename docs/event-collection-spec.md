# Event Collection Specification
## theData.io Universal Data Platform

## Table of Contents
1. [Overview](#1-overview)
2. [Event Categories](#2-event-categories)
3. [Client SDKs](#3-client-sdks)
4. [Server-Side Collection](#4-server-side-collection)
5. [Schema Definitions](#5-schema-definitions)
6. [Processing Pipeline](#6-processing-pipeline)
7. [Team-Specific Insights](#7-team-specific-insights)

## 1. Overview

### 1.1 Purpose
This document defines the event collection architecture for theData.io platform, designed to provide end-to-end visibility from user interaction to database operations.

### 1.2 Design Principles
- Collect raw, unprocessed events
- Maintain data lineage
- Enable cross-platform correlation
- Support real-time and batch processing
- Ensure data quality and completeness
- Optimize for query performance
- Enable custom event tracking

## 2. Event Categories

### 2.1 Client-Side Events

#### 2.1.1 User Interaction Events
```typescript
interface UserInteractionEvent {
    event_id: string;
    timestamp: string;
    platform: string;  // ios, android, web, etc.
    device_info: {
        type: string;
        os: string;
        version: string;
        manufacturer: string;
    };
    session_id: string;
    user_id?: string;
    event_type: string;
    event_name: string;
    properties: {
        screen_name?: string;
        element_id?: string;
        element_type?: string;
        action: string;
        value?: any;
    };
    context: {
        app_version: string;
        network_type: string;
        carrier?: string;
        locale: string;
        timezone: string;
    };
}
```

#### 2.1.2 Performance Events
```typescript
interface PerformanceEvent {
    event_id: string;
    timestamp: string;
    platform: string;
    event_type: "performance";
    category: "network" | "rendering" | "memory" | "battery";
    measurements: {
        name: string;
        value: number;
        unit: string;
    }[];
    context: {
        session_id: string;
        view_name?: string;
        network_info?: {
            type: string;
            strength: number;
        };
    };
}
```

#### 2.1.3 Video Analytics Events
```typescript
interface VideoEvent {
    event_id: string;
    timestamp: string;
    platform: string;
    event_type: "video";
    video_id: string;
    player_type: string;
    event_name: "start" | "pause" | "buffer" | "quality_change" | "error";
    measurements: {
        startup_time?: number;
        buffer_duration?: number;
        bitrate?: number;
        resolution?: string;
        fps?: number;
        latency?: number;
    };
    quality_metrics: {
        video_quality_score: number;
        buffering_ratio: number;
        startup_time_score: number;
    };
    context: {
        cdn_provider: string;
        player_version: string;
        drm_type?: string;
    };
}
```

### 2.2 Server-Side Events

#### 2.2.1 Application Metrics
```typescript
interface ApplicationMetric {
    metric_id: string;
    timestamp: string;
    service: string;
    environment: string;
    metric_type: "counter" | "gauge" | "histogram";
    name: string;
    value: number;
    labels: Record<string, string>;
    host_info: {
        hostname: string;
        ip: string;
        region: string;
    };
}
```

#### 2.2.2 Distributed Traces
```typescript
interface DistributedTrace {
    trace_id: string;
    span_id: string;
    parent_span_id?: string;
    service: string;
    operation: string;
    start_time: string;
    end_time: string;
    duration_ms: number;
    status: "success" | "error";
    attributes: {
        http_method?: string;
        http_url?: string;
        http_status_code?: number;
        db_statement?: string;
        error_message?: string;
    };
    resource: {
        service_name: string;
        service_version: string;
        host_name: string;
    };
}
```

#### 2.2.3 Log Events
```typescript
interface LogEvent {
    log_id: string;
    timestamp: string;
    service: string;
    level: "debug" | "info" | "warn" | "error" | "fatal";
    message: string;
    logger_name: string;
    thread_name?: string;
    stack_trace?: string;
    context: {
        request_id?: string;
        user_id?: string;
        trace_id?: string;
    };
    metadata: Record<string, any>;
}
```

#### 2.2.4 Infrastructure Metrics
```typescript
interface InfrastructureMetric {
    metric_id: string;
    timestamp: string;
    resource_type: "container" | "vm" | "function" | "database";
    resource_id: string;
    provider: string;
    region: string;
    measurements: {
        cpu_usage: number;
        memory_usage: number;
        disk_io: number;
        network_io: number;
    };
    cost_data?: {
        cost_per_hour: number;
        currency: string;
    };
}
```

## 3. Client SDKs

### 3.1 Core SDK Features
- Automatic event collection
- Configurable sampling rates
- Offline event caching
- Batch uploading
- Automatic retry logic
- Data compression
- Privacy controls

### 3.2 Platform-Specific SDKs
1. **Web SDK**
   - Browser performance monitoring
   - SPA route changes
   - Error tracking
   - User session recording

2. **iOS SDK**
   - Native crash reporting
   - Network monitoring
   - Battery impact tracking
   - Screen render timing

3. **Android SDK**
   - ANR detection
   - Memory leaks
   - Battery consumption
   - UI performance

4. **React Native SDK**
   - Bridge performance
   - Native module usage
   - JavaScript errors
   - Navigation timing

5. **Flutter SDK**
   - Widget rebuilds
   - Frame timing
   - Memory profiling
   - Platform channel usage

6. **Smart TV / Set-top Box SDK**
   - Video playback metrics
   - Remote control interactions
   - Memory constraints
   - Background processes

7. **IoT SDK**
   - Resource-optimized
   - Battery awareness
   - Intermittent connectivity
   - Limited storage handling

## 4. Server-Side Collection

### 4.1 Collection Methods
1. **Direct Integration**
   - API endpoints
   - SDK integration
   - Agent-based collection

2. **Infrastructure Integration**
   - Cloud provider metrics
   - Container orchestration
   - Load balancer metrics

3. **Application Integration**
   - OpenTelemetry
   - Prometheus exporters
   - Log shippers

### 4.2 Data Processing
1. **Real-time Processing**
   - Event validation
   - Enrichment
   - Correlation
   - Aggregation

2. **Batch Processing**
   - Historical analysis
   - Trend computation
   - Report generation
   - Data cleanup

## 5. Schema Definitions

### 5.1 Base Event Schema
```sql
CREATE TABLE events (
    event_id UUID,
    timestamp DateTime64(9),
    platform LowCardinality(String),
    event_type LowCardinality(String),
    event_name String,
    session_id UUID,
    user_id UUID,
    properties JSON,
    context JSON,
    raw_data String,
    processed_at DateTime64(9),
    _partition_key String
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(timestamp)
ORDER BY (timestamp, event_type, event_id);
```

### 5.2 Specialized Tables
- Video analytics
- Performance metrics
- User sessions
- Error tracking
- Cost analysis

## 6. Processing Pipeline

### 6.1 Event Flow
1. Collection
2. Validation
3. Enrichment
4. Storage
5. Processing
6. Aggregation
7. Analysis

### 6.2 Data Transformations
- Session stitching
- User journey mapping
- Funnel analysis
- Anomaly detection
- Cost attribution

## 7. Team-Specific Insights

### 7.1 Marketing Team
- User acquisition channels
- Campaign performance
- Conversion funnels
- Attribution modeling
- Engagement metrics

### 7.2 Product Team
- Feature usage
- User flows
- A/B test results
- Retention metrics
- User feedback

### 7.3 Engineering Teams
- Performance metrics
- Error rates
- System health
- API usage
- Technical debt indicators

### 7.4 Video Engineering Team
- Playback quality
- Streaming performance
- CDN optimization
- Player analytics
- DRM insights

### 7.5 Operations Team
- System availability
- Resource utilization
- Incident metrics
- SLA compliance
- Capacity planning

### 7.6 Security Team
- Access patterns
- Threat indicators
- Compliance metrics
- Vulnerability tracking
- Security posture

### 7.7 Cost Management Team
- Resource costs
- Usage patterns
- Optimization opportunities
- Budget tracking
- ROI analysis

---

This document serves as the foundation for implementing the event collection system. It should be updated as requirements evolve and new use cases are identified. 