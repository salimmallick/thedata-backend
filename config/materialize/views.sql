-- Create JSON validation functions
CREATE FUNCTION validate_metric_json(data text) RETURNS bool AS $$
SELECT 
    (data::json->>'timestamp') IS NOT NULL AND
    (data::json->>'name') IS NOT NULL AND
    (data::json->>'value') IS NOT NULL AND
    (data::json->>'tags') IS NOT NULL;
$$ LANGUAGE sql;

CREATE FUNCTION validate_event_json(data text) RETURNS bool AS $$
SELECT 
    (data::json->>'timestamp') IS NOT NULL AND
    (data::json->>'event_type') IS NOT NULL AND
    (data::json->>'properties') IS NOT NULL;
$$ LANGUAGE sql;

-- Create sources with validation
CREATE SOURCE raw_metrics_source
FROM NATS
  TOPIC 'metrics.>'
  FORMAT BYTES
  ENVELOPE NONE;

CREATE SOURCE raw_events_source
FROM NATS
  TOPIC 'events.>'
  FORMAT BYTES
  ENVELOPE NONE;

-- Create validated sources
CREATE VIEW valid_metrics AS
SELECT 
    (data::json->>'timestamp')::timestamp as timestamp,
    data::json->>'name' as name,
    (data::json->>'value')::float8 as value,
    data::json->>'tags' as tags
FROM raw_metrics_source
WHERE validate_metric_json(convert_from(data, 'utf8'));

CREATE VIEW valid_events AS
SELECT 
    (data::json->>'timestamp')::timestamp as timestamp,
    data::json->>'event_type' as event_type,
    data::json->>'user_id' as user_id,
    data::json->>'properties' as properties
FROM raw_events_source
WHERE validate_event_json(convert_from(data, 'utf8'));

-- Create error tracking views
CREATE MATERIALIZED VIEW invalid_metrics AS
SELECT 
    convert_from(data, 'utf8') as raw_data,
    mz_logical_timestamp as error_timestamp
FROM raw_metrics_source
WHERE NOT validate_metric_json(convert_from(data, 'utf8'));

CREATE MATERIALIZED VIEW invalid_events AS
SELECT 
    convert_from(data, 'utf8') as raw_data,
    mz_logical_timestamp as error_timestamp
FROM raw_events_source
WHERE NOT validate_event_json(convert_from(data, 'utf8'));

-- Create windowed metrics views
CREATE MATERIALIZED VIEW metrics_last_hour AS
SELECT
    name,
    avg(value) as avg_value,
    min(value) as min_value,
    max(value) as max_value,
    count(*) as count,
    approx_percentile(value, 0.95) as p95,
    max(timestamp) as last_update
FROM valid_metrics
WHERE timestamp > (NOW() - INTERVAL '1 hour')
GROUP BY name
HAVING count(*) > 0
PERSIST TO 'metrics_last_hour'
WITH (recovery_mode = 'PERSIST_ONLY');

-- Create event analysis views
CREATE MATERIALIZED VIEW event_counts AS
SELECT
    event_type,
    count(*) as count,
    count(DISTINCT user_id) as unique_users,
    max(timestamp) as last_update
FROM valid_events
WHERE timestamp > (NOW() - INTERVAL '1 hour')
GROUP BY event_type
PERSIST TO 'event_counts'
WITH (recovery_mode = 'PERSIST_ONLY');

-- Create session tracking with persistence
CREATE MATERIALIZED VIEW user_sessions AS
WITH session_boundaries AS (
    SELECT
        user_id,
        timestamp as event_time,
        CASE 
            WHEN timestamp - LAG(timestamp) OVER (PARTITION BY user_id ORDER BY timestamp) > INTERVAL '30 minutes'
            THEN 1
            ELSE 0
        END as is_new_session
    FROM valid_events
    WHERE user_id IS NOT NULL
)
SELECT
    user_id,
    SUM(is_new_session) OVER (PARTITION BY user_id ORDER BY event_time) as session_id,
    min(event_time) as session_start,
    max(event_time) as session_end,
    count(*) as event_count
FROM session_boundaries
WHERE event_time > (NOW() - INTERVAL '4 hours')
GROUP BY user_id, session_id
PERSIST TO 'user_sessions'
WITH (recovery_mode = 'PERSIST_ONLY');

-- Create anomaly detection with persistence
CREATE MATERIALIZED VIEW metric_anomalies AS
WITH hourly_stats AS (
    SELECT
        name,
        timestamp_trunc('hour', timestamp) as hour,
        avg(value) as avg_value,
        stddev(value) as stddev_value,
        count(*) as sample_count
    FROM valid_metrics
    WHERE timestamp > (NOW() - INTERVAL '24 hours')
    GROUP BY name, timestamp_trunc('hour', timestamp)
),
baseline AS (
    SELECT
        name,
        avg(avg_value) as baseline_avg,
        avg(stddev_value) as baseline_stddev,
        sum(sample_count) as total_samples
    FROM hourly_stats
    GROUP BY name
    HAVING sum(sample_count) > 100
)
SELECT
    m.name,
    m.value,
    m.timestamp,
    b.baseline_avg,
    b.baseline_stddev,
    (m.value - b.baseline_avg) / NULLIF(b.baseline_stddev, 0) as z_score,
    b.total_samples as baseline_samples
FROM valid_metrics m
JOIN baseline b ON m.name = b.name
WHERE 
    abs((m.value - b.baseline_avg) / NULLIF(b.baseline_stddev, 0)) > 3
    AND m.timestamp > (NOW() - INTERVAL '5 minutes')
PERSIST TO 'metric_anomalies'
WITH (recovery_mode = 'PERSIST_ONLY');

-- Create data quality metrics
CREATE MATERIALIZED VIEW data_quality_metrics AS
SELECT
    'metrics' as source,
    count(*) as total_records,
    sum(CASE WHEN validate_metric_json(convert_from(data, 'utf8')) THEN 1 ELSE 0 END) as valid_records,
    sum(CASE WHEN NOT validate_metric_json(convert_from(data, 'utf8')) THEN 1 ELSE 0 END) as invalid_records,
    min(mz_logical_timestamp) as first_seen,
    max(mz_logical_timestamp) as last_seen
FROM raw_metrics_source
UNION ALL
SELECT
    'events' as source,
    count(*) as total_records,
    sum(CASE WHEN validate_event_json(convert_from(data, 'utf8')) THEN 1 ELSE 0 END) as valid_records,
    sum(CASE WHEN NOT validate_event_json(convert_from(data, 'utf8')) THEN 1 ELSE 0 END) as invalid_records,
    min(mz_logical_timestamp) as first_seen,
    max(mz_logical_timestamp) as last_seen
FROM raw_events_source; 