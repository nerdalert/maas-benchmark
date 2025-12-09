# Control Plane and etcd Monitoring for MaaS Benchmarks

Monitor etcd and authentication pipeline performance during MaaS benchmarking to identify bottlenecks.

## Prerequisites

### 1. Relax Rate Limits
Before running performance tests, increase rate limits to avoid throttling. See [README.md](../README.md) for commands:

```bash
# Increase RateLimitPolicy limits (requests per 2 minutes)
kubectl patch ratelimitpolicy gateway-rate-limits -n openshift-ingress --type='json' -p='[
  {"op": "replace", "path": "/spec/limits/free/rates/0/limit", "value": 10000},
  {"op": "replace", "path": "/spec/limits/premium/rates/0/limit", "value": 10000},
  {"op": "replace", "path": "/spec/limits/enterprise/rates/0/limit", "value": 10000}
]'

# Increase TokenRateLimitPolicy limits (tokens per 1 minute)
kubectl patch tokenratelimitpolicy gateway-token-rate-limits -n openshift-ingress --type='json' -p='[
  {"op": "replace", "path": "/spec/limits/free-user-tokens/rates/0/limit", "value": 10000000},
  {"op": "replace", "path": "/spec/limits/premium-user-tokens/rates/0/limit", "value": 10000000},
  {"op": "replace", "path": "/spec/limits/enterprise-user-tokens/rates/0/limit", "value": 10000000}
]'
```

### 2. Service Monitor Setup
Apply service monitors to enable metrics collection:

```bash
# Apply all service monitors
kubectl apply -f infra/service-monitors/

# Verify service monitors are applied
kubectl get servicemonitor -A | grep -E "(etcd|auth|prometheus)"
```

## Quick Setup

```bash
# Discover cluster and set variables
CLUSTER_DOMAIN=$(kubectl get ingresses.config.openshift.io cluster -o jsonpath='{.spec.domain}')
PROM_HOST="thanos-querier-openshift-monitoring.${CLUSTER_DOMAIN}"
HOST="maas.${CLUSTER_DOMAIN}"
TOKEN=$(oc whoami -t)
MODEL_NAME="facebook/opt-125m"

# Verify Prometheus connection
curl -sk -H "Authorization: Bearer ${TOKEN}" "https://${PROM_HOST}/api/v1/query?query=up" | jq -r '.status'
# Expected: success
```

## etcd Metrics

### Request Rates by Operation

```bash
# etcd request rate by operation (requests/sec)
curl -sk -H "Authorization: Bearer ${TOKEN}" "https://${PROM_HOST}/api/v1/query" \
  --data-urlencode 'query=sum(rate(etcd_requests_total[5m])) by (operation)' \
  | jq '.data.result[] | {operation: .metric.operation, rate_per_sec: .value[1]}'
```

### P99 Latency by Operation

```bash
# P99 etcd request latency by operation (seconds)
curl -sk -H "Authorization: Bearer ${TOKEN}" "https://${PROM_HOST}/api/v1/query" \
  --data-urlencode 'query=histogram_quantile(0.99, sum(rate(etcd_request_duration_seconds_bucket[5m])) by (le, operation))' \
  | jq '.data.result[] | {operation: .metric.operation, p99_latency_sec: .value[1]}'
```

### Error Rate

```bash
# etcd error rate
curl -sk -H "Authorization: Bearer ${TOKEN}" "https://${PROM_HOST}/api/v1/query" \
  --data-urlencode 'query=sum(rate(etcd_request_errors_total[5m]))' \
  | jq '.data.result[0].value[1]'
```

## Authentication Pipeline Metrics

### TokenReview Latency and Rate

```bash
# P99 authentication latency (TokenReview)
curl -sk -H "Authorization: Bearer ${TOKEN}" "https://${PROM_HOST}/api/v1/query" \
  --data-urlencode 'query=histogram_quantile(0.99, rate(authentication_duration_seconds_bucket[5m]))' \
  | jq '.data.result'

# Authentication request rate (per second)
curl -sk -H "Authorization: Bearer ${TOKEN}" "https://${PROM_HOST}/api/v1/query" \
  --data-urlencode 'query=sum(rate(authentication_attempts[5m]))' \
  | jq '.data.result[0].value[1]'

# Token cache hit rate (higher = better, reduces TokenReview calls)
curl -sk -H "Authorization: Bearer ${TOKEN}" "https://${PROM_HOST}/api/v1/query" \
  --data-urlencode 'query=sum(rate(authentication_token_cache_request_total{status="hit"}[5m])) / sum(rate(authentication_token_cache_request_total[5m]))' \
  | jq '.data.result[0].value[1]'
```

### SubjectAccessReview Latency

```bash
# P99 authorization latency
curl -sk -H "Authorization: Bearer ${TOKEN}" "https://${PROM_HOST}/api/v1/query" \
  --data-urlencode 'query=histogram_quantile(0.99, rate(authorization_duration_seconds_bucket[5m]))' \
  | jq '.data.result'

# Authorization decisions by result
curl -sk -H "Authorization: Bearer ${TOKEN}" "https://${PROM_HOST}/api/v1/query" \
  --data-urlencode 'query=sum(rate(apiserver_authorization_decisions_total[5m])) by (decision)' \
  | jq '.data.result'
```

## Run Benchmarks with Monitoring

### Step 1: Record Start Time

```bash
START_TIME=$(date +%s)
echo "Start time: ${START_TIME}"
```

### Step 2: Run Benchmark

```bash
# Burst test with 20 concurrent users, 20 iterations each
HOST=${HOST} MODEL_NAME=${MODEL_NAME} BURST_VUS=20 BURST_ITERATIONS=20 \
  k6 run k6/maas-performance-test.js
```

### Step 3: Capture End Time and Duration

```bash
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME + 60))  # Add 1 min buffer
echo "Duration: ${DURATION} seconds"
```

### Step 4: Query Metrics for Test Period

```bash
# etcd request rate over test period
curl -sk -H "Authorization: Bearer ${TOKEN}" "https://${PROM_HOST}/api/v1/query_range" \
  --data-urlencode 'query=sum(rate(etcd_requests_total[1m])) by (operation)' \
  --data-urlencode "start=${START_TIME}" \
  --data-urlencode "end=${END_TIME}" \
  --data-urlencode "step=15" \
  | jq

# Auth latency over test period
curl -sk -H "Authorization: Bearer ${TOKEN}" "https://${PROM_HOST}/api/v1/query_range" \
  --data-urlencode 'query=histogram_quantile(0.99, rate(authentication_duration_seconds_bucket[1m]))' \
  --data-urlencode "start=${START_TIME}" \
  --data-urlencode "end=${END_TIME}" \
  --data-urlencode "step=15" \
  | jq
```

## Soak Test with Background Monitoring

Run an extended soak test while monitoring etcd metrics.

### Step 1: Start Soak Test in Background

```bash
# Record start time
START_TIME=$(date +%s)
echo ${START_TIME} > /tmp/soak_start_time

# Run soak test in background (5 concurrent users, 10000 iterations)
HOST=${HOST} MODEL_NAME=${MODEL_NAME} BURST_VUS=5 BURST_ITERATIONS=10000 \
  k6 run k6/maas-performance-test.js &
```

### Step 2: Monitor During Test

While the test runs, periodically check metrics:

```bash
# Check current etcd request rates
curl -sk -H "Authorization: Bearer ${TOKEN}" "https://${PROM_HOST}/api/v1/query" \
  --data-urlencode 'query=sum(rate(etcd_requests_total[1m])) by (operation)' \
  | jq '.data.result[] | {op: .metric.operation, rate: .value[1]}'

# Check current auth rate
curl -sk -H "Authorization: Bearer ${TOKEN}" "https://${PROM_HOST}/api/v1/query" \
  --data-urlencode 'query=sum(rate(authentication_attempts[1m]))' \
  | jq '.data.result[0].value[1]'

# Check etcd P99 latency
curl -sk -H "Authorization: Bearer ${TOKEN}" "https://${PROM_HOST}/api/v1/query" \
  --data-urlencode 'query=histogram_quantile(0.99, sum(rate(etcd_request_duration_seconds_bucket[1m])) by (le, operation))' \
  | jq '.data.result[] | {op: .metric.operation, p99_ms: (.value[1] | tonumber * 1000)}'
```

### Step 3: Capture Metrics After Test

```bash
# Get start time from file
START_TIME=$(cat /tmp/soak_start_time)
END_TIME=$(date +%s)

# Save etcd request rate time series
curl -sk -H "Authorization: Bearer ${TOKEN}" "https://${PROM_HOST}/api/v1/query_range" \
  --data-urlencode 'query=sum(rate(etcd_requests_total[1m])) by (operation)' \
  --data-urlencode "start=${START_TIME}" \
  --data-urlencode "end=${END_TIME}" \
  --data-urlencode "step=15" \
  | jq > results/etcd_request_rate.json

# Save etcd latency time series
curl -sk -H "Authorization: Bearer ${TOKEN}" "https://${PROM_HOST}/api/v1/query_range" \
  --data-urlencode 'query=histogram_quantile(0.99, sum(rate(etcd_request_duration_seconds_bucket[1m])) by (le, operation))' \
  --data-urlencode "start=${START_TIME}" \
  --data-urlencode "end=${END_TIME}" \
  --data-urlencode "step=15" \
  | jq > results/etcd_p99_latency.json

# Save auth latency time series
curl -sk -H "Authorization: Bearer ${TOKEN}" "https://${PROM_HOST}/api/v1/query_range" \
  --data-urlencode 'query=histogram_quantile(0.99, rate(authentication_duration_seconds_bucket[1m]))' \
  --data-urlencode "start=${START_TIME}" \
  --data-urlencode "end=${END_TIME}" \
  --data-urlencode "step=15" \
  | jq > results/auth_p99_latency.json
```

## Breakpoint Testing

Find the concurrency level where the system breaks down.

```bash
# Test at increasing concurrency levels
for VUS in 1 5 10 15 20 22 25 30 50 100; do
  echo "=== Testing ${VUS} concurrent users ==="
  HOST=${HOST} MODEL_NAME=${MODEL_NAME} BURST_VUS=${VUS} BURST_ITERATIONS=${VUS} \
    k6 run k6/maas-performance-test.js 2>&1 | grep -E "(success_rate|http_req_duration)"
  sleep 5
done
```

### Individual Commands for Each Level

```bash
# 1 concurrent user
HOST=${HOST} MODEL_NAME=${MODEL_NAME} BURST_VUS=1 BURST_ITERATIONS=1 k6 run k6/maas-performance-test.js

# 5 concurrent users
HOST=${HOST} MODEL_NAME=${MODEL_NAME} BURST_VUS=5 BURST_ITERATIONS=5 k6 run k6/maas-performance-test.js

# 10 concurrent users
HOST=${HOST} MODEL_NAME=${MODEL_NAME} BURST_VUS=10 BURST_ITERATIONS=10 k6 run k6/maas-performance-test.js

# 15 concurrent users
HOST=${HOST} MODEL_NAME=${MODEL_NAME} BURST_VUS=15 BURST_ITERATIONS=15 k6 run k6/maas-performance-test.js

# 20 concurrent users
HOST=${HOST} MODEL_NAME=${MODEL_NAME} BURST_VUS=20 BURST_ITERATIONS=20 k6 run k6/maas-performance-test.js

# 22 concurrent users
HOST=${HOST} MODEL_NAME=${MODEL_NAME} BURST_VUS=22 BURST_ITERATIONS=22 k6 run k6/maas-performance-test.js

# 25 concurrent users
HOST=${HOST} MODEL_NAME=${MODEL_NAME} BURST_VUS=25 BURST_ITERATIONS=25 k6 run k6/maas-performance-test.js

# 30 concurrent users
HOST=${HOST} MODEL_NAME=${MODEL_NAME} BURST_VUS=30 BURST_ITERATIONS=30 k6 run k6/maas-performance-test.js

# 50 concurrent users
HOST=${HOST} MODEL_NAME=${MODEL_NAME} BURST_VUS=50 BURST_ITERATIONS=50 k6 run k6/maas-performance-test.js

# 100 concurrent users
HOST=${HOST} MODEL_NAME=${MODEL_NAME} BURST_VUS=100 BURST_ITERATIONS=100 k6 run k6/maas-performance-test.js
```

## List Available Metrics

```bash
# All etcd metrics
curl -sk -H "Authorization: Bearer ${TOKEN}" "https://${PROM_HOST}/api/v1/label/__name__/values" \
  | jq '.data | map(select(startswith("etcd")))'

# All auth metrics
curl -sk -H "Authorization: Bearer ${TOKEN}" "https://${PROM_HOST}/api/v1/label/__name__/values" \
  | jq '.data | map(select(contains("authentication") or contains("authorization")))'
```

## Benchmark Results

### Breakpoint Analysis (with rate limits disabled)

| Concurrent Users | Success Rate | Avg Latency | Status |
|-----------------|--------------|-------------|--------|
| 5 | 99.93% | 67ms | Healthy |
| 20 | 95% | 227ms | Healthy |
| 25 | 76% | 246ms | Degraded |
| 30 | 64% | 306ms | Failing |
| 40 | 43% | 296ms | Critical |
| 50 | 18% | 292ms | Broken |

### etcd Metrics During High Load

| Operation | P99 Latency | Rate (req/s) | Status |
|-----------|-------------|--------------|--------|
| GET | 22ms | ~1000/s | Healthy |
| UPDATE | 4ms | ~300/s | Healthy |
| CREATE | 38ms | ~15/s | Healthy |
| LIST | 4ms | ~10/s | Healthy |

### Conclusions

**etcd is NOT the bottleneck** - all P99 latencies remain < 50ms even when system is failing at 50 concurrent users.

### Observed Performance During Testing

**K8s API Server Performance (Excellent):**
- **TokenReview P99 latency**: ~7.8ms
- **SubjectAccessReview P99 latency**: ~7.7-12ms
- API server responds in single-digit to low double-digit milliseconds

**etcd Performance (Excellent):**

**Extreme Load Test Results (100 VUs, 1M iterations):**

etcd handled **massive load** without degradation:
- **Peak: 1,098 GET req/s, 382 UPDATE req/s, 37 CREATE req/s**
- P99 latencies remained **rock-solid**: GET 18-23ms, UPDATE 4ms, CREATE 24-39ms
- No etcd errors or timeouts observed

**Confirmed Bottleneck: Authorino K8s Client Rate Limiter**
- Auth service degraded to **42% success rate** under extreme load
- **58% error rate** and **54% timeout rate**
- 149,309 total auth requests processed during monitoring period
- etcd performance remained excellent throughout auth service degradation

### Extreme Load Test Metrics Table

| Time Elapsed | etcd GET/s | etcd UPDATE/s | GET P99 | UPDATE P99 | Auth Success % |
|--------------|------------|---------------|---------|------------|----------------|
| 0:00 | 995.2 | 316.2 | 22ms | 4ms | 53.7% |
| 0:31 | 949.8 | 305.3 | 22ms | 4ms | 50.4% |
| 1:03 | 895.6 | 294.2 | 22ms | 4ms | 47.8% |
| 1:34 | 849.0 | 285.8 | 22ms | 4ms | - |
| 2:05 | 823.2 | 277.0 | 22ms | 4ms | - |
| 2:37 | 776.5 | 265.8 | 22ms | 4ms | - |
| 3:08 | 731.8 | 255.4 | 22ms | 4ms | - |
| 5:30 | 575-586 | 296-301 | 18-19ms | 24ms | - |
| 10:05 | 1,098 | 382 | 22ms | 4ms | 42.4% |

**Final Auth Service Breakdown:**
- **Total Requests**: 149,309
- **Successes**: 63,310 (42.4% success rate)
- **Errors**: 85,964 (57.6% error rate)
- **Timeouts**: 80,775 (54.1% timeout rate)

**Key Observation**: Even with 58% auth failure rate, etcd maintained excellent P99 latencies (18-23ms) and handled peak throughput of 1,098 GET req/s + 382 UPDATE req/s.

## Hosted Control Plane Note

On ROSA with hosted control plane (HCP), etcd runs in a separate management cluster. Available metrics show the **client-side view** from the apiserver:

- `etcd_request_duration_seconds` - Latency from apiserver to etcd
- `etcd_requests_total` - Request counts by operation (get, list, update, create, delete)
- `etcd_request_errors_total` - Error counts

Internal etcd metrics (WAL fsync, proposals pending, DB size) require access to the management cluster's Prometheus.
