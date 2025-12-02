# MaaS Benchmarking Quickstart

## Prerequisites
- Authenticated to OpenShift: `oc login`
- k6 installed
- MaaS deployment running

## 0. Setup

### Upgrade Kuadrant to Latest (Optional)
```bash
# Bump Kuadrant operator to latest version
kubectl patch csv kuadrant-operator.v1.3.0 -n kuadrant-system --type='json' \
  -p='[{"op": "replace", "path": "/spec/install/spec/deployments/0/spec/template/spec/containers/0/image", "value": "quay.io/kuadrant/kuadrant-operator:latest"}]'

# Verify the operator pod restarts with new image
kubectl get pods -n kuadrant-system -l control-plane=controller-manager -w
```

### Adjust Rate Limits for Scale Testing (Optional)

For scale/performance testing, increase rate limits to avoid hitting quotas during tests:

```bash
# Check current rate limit policies
kubectl get ratelimitpolicy -A
kubectl get tokenratelimitpolicy -A

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

# Verify the changes
kubectl get ratelimitpolicy gateway-rate-limits -n openshift-ingress -o jsonpath='{.spec.limits.free.rates[0].limit}'
# Should show: 10000

kubectl get tokenratelimitpolicy gateway-token-rate-limits -n openshift-ingress -o jsonpath='{.spec.limits.free-user-tokens.rates[0].limit}'
# Should show: 10000000
```

To restore original limits after testing:
```bash
# Restore RateLimitPolicy (5/20/50 per 2 min)
kubectl patch ratelimitpolicy gateway-rate-limits -n openshift-ingress --type='json' -p='[
  {"op": "replace", "path": "/spec/limits/free/rates/0/limit", "value": 5},
  {"op": "replace", "path": "/spec/limits/premium/rates/0/limit", "value": 20},
  {"op": "replace", "path": "/spec/limits/enterprise/rates/0/limit", "value": 50}
]'

# Restore TokenRateLimitPolicy (100/50000/100000 per 1 min)
kubectl patch tokenratelimitpolicy gateway-token-rate-limits -n openshift-ingress --type='json' -p='[
  {"op": "replace", "path": "/spec/limits/free-user-tokens/rates/0/limit", "value": 100},
  {"op": "replace", "path": "/spec/limits/premium-user-tokens/rates/0/limit", "value": 50000},
  {"op": "replace", "path": "/spec/limits/enterprise-user-tokens/rates/0/limit", "value": 100000}
]'
```

## 1. Create Service Account Tokens

Create multiple service accounts with unique tokens for multi-user benchmarking:

```bash
cd maas-benchmarking

# Create 10 free tier service accounts with tokens
FREE_USERS=10 PREMIUM_USERS=0 ./scripts/create-sa-tokens.sh

# Or with custom expiration (default is 2h)
TOKEN_EXPIRATION="4h" FREE_USERS=10 PREMIUM_USERS=0 ./scripts/create-sa-tokens.sh

# Verify tokens were created
./scripts/token-manager.sh status
```

This creates:
- Service accounts: `benchuser-free-1`, `benchuser-free-2`, etc.
- Kubernetes tokens with correct audience for MaaS gateway
- Each SA has a unique name for independent rate limiting

## 2. Run Benchmarks

Run k6 performance tests directly with environment variables:

```bash
# Set your MaaS host (replace with your actual host)
export HOST="your-maas-host.apps.example.com"
export MODEL_NAME="facebook/opt-125m"

# Basic test: 5 concurrent users, 10 requests each
HOST=$HOST MODEL_NAME=$MODEL_NAME BURST_VUS=5 BURST_ITERATIONS=10 k6 run k6/maas-performance-test.js

# Moderate load: 10 concurrent users, 20 requests each
HOST=$HOST MODEL_NAME=$MODEL_NAME BURST_VUS=10 BURST_ITERATIONS=20 k6 run k6/maas-performance-test.js

# High concurrency: 30 concurrent users, 30 requests each
HOST=$HOST MODEL_NAME=$MODEL_NAME BURST_VUS=30 BURST_ITERATIONS=30 k6 run k6/maas-performance-test.js

# Sustained load test (soak mode)
HOST=$HOST MODEL_NAME=$MODEL_NAME MODE=soak SOAK_DURATION=5m SOAK_RATE_FREE=2 k6 run k6/maas-performance-test.js
```

**Environment Variables:**
- `HOST` - MaaS hostname (without https://)
- `MODEL_NAME` - Model to test (e.g., facebook/opt-125m)
- `BURST_VUS` - Number of concurrent virtual users
- `BURST_ITERATIONS` - Total iterations to run
- `MODE` - Test mode: `burst` (default), `soak`, or `rate-limit-test`

## 4. View Results

```bash
# Latest test results
ls -lth results/*.json | head -5

# View summary with better formatting
cat results/test_*_summary.json | jq
```

## 5. Cleanup

```bash
# Remove service accounts and tokens
FREE_USERS=10 PREMIUM_USERS=0 ./scripts/cleanup-sa-tokens.sh

# Keep tokens but clean service accounts
FREE_USERS=10 PREMIUM_USERS=0 CLEAN_TOKENS=false ./scripts/cleanup-sa-tokens.sh

# Or just remove token files
./scripts/token-manager.sh clean
```

## Quick Reference

**Common Test Patterns:**
```bash
export HOST="your-maas-host.apps.example.com"
export MODEL_NAME="facebook/opt-125m"

# Single user baseline
HOST=$HOST MODEL_NAME=$MODEL_NAME BURST_VUS=1 BURST_ITERATIONS=1 k6 run k6/maas-performance-test.js

# Safe concurrent load (recommended)
HOST=$HOST MODEL_NAME=$MODEL_NAME BURST_VUS=3 BURST_ITERATIONS=10 k6 run k6/maas-performance-test.js

# Breaking point test (will likely fail)
HOST=$HOST MODEL_NAME=$MODEL_NAME BURST_VUS=30 BURST_ITERATIONS=30 k6 run k6/maas-performance-test.js

# Sustained load (soak test)
HOST=$HOST MODEL_NAME=$MODEL_NAME MODE=soak SOAK_DURATION=2m SOAK_RATE_FREE=5 k6 run k6/maas-performance-test.js
```

**Scale to More Users:**
```bash
# Create 50 service accounts
FREE_USERS=50 PREMIUM_USERS=0 ./scripts/create-sa-tokens.sh
```

