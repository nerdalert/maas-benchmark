# Simple Auth Baseline for Performance Testing

Lightweight API key authentication baseline to compare against TokenReview + SubjectAccessReview performance.

## Architecture

**Simple Auth Path:**
```
Request → Gateway → API Key Validation (local) → Model Service
```

## Components

- `api-keys.yaml` - 5 pre-shared API keys
- `routes.yaml` - HTTPRoute for `/simple/llm/...` path
- `auth-policy.yaml` - AuthPolicy using API keys only
- `kustomization.yaml` - Manages all resources

## Deploy

```bash
cd ~/maas-bench/maas-benchmarking/infra/simple-auth
kubectl apply -k .

# Verify
kubectl get secrets -n openshift-ingress -l app=maas-simple-auth
kubectl get httproute simple-auth-model-route -n llm
kubectl get authpolicy simple-auth-policy -n llm
```

## Test

```bash
# Set environment
CLUSTER_DOMAIN=$(kubectl get ingresses.config.openshift.io cluster -o jsonpath='{.spec.domain}')
export HOST="maas.${CLUSTER_DOMAIN}"

# Test with valid API key (should return 200)
curl -sSk -w "\nHTTP: %{http_code}\n" \
  -H "Authorization: APIKEY perftest-user1-key" \
  -H "Content-Type: application/json" \
  -d '{"model": "facebook/opt-125m", "prompt": "Hello", "max_tokens": 50}' \
  "http://$HOST/simple/llm/facebook-opt-125m-simulated/v1/completions"

# Test with invalid API key (should return 401)
curl -sSk -w "\nHTTP: %{http_code}\n" \
  -H "Authorization: APIKEY invalid-key" \
  -H "Content-Type: application/json" \
  -d '{"model": "facebook/opt-125m", "prompt": "Hello", "max_tokens": 50}' \
  "http://$HOST/simple/llm/facebook-opt-125m-simulated/v1/completions"
```

## Performance Testing with k6

```bash
cd ~/maas-bench/maas-benchmarking

# Single request debug test
HOST=$HOST MODEL_NAME=facebook/opt-125m BURST_VUS=1 BURST_ITERATIONS=1 DEBUG=true k6 run k6/simple-auth/simple-auth-test.js

# 5 users, 20 requests each (100 total)
HOST=$HOST MODEL_NAME=facebook/opt-125m BURST_VUS=5 BURST_ITERATIONS=20 k6 run k6/simple-auth/simple-auth-test.js

# 20 users, 20 requests each (400 total)
HOST=$HOST MODEL_NAME=facebook/opt-125m BURST_VUS=20 BURST_ITERATIONS=20 k6 run k6/simple-auth/simple-auth-test.js

# 30 concurrent users, 1 request each
HOST=$HOST MODEL_NAME=facebook/opt-125m BURST_VUS=30 BURST_ITERATIONS=1 k6 run k6/simple-auth/simple-auth-test.js

# 30 concurrent users, 30 requests each (900 total)
HOST=$HOST MODEL_NAME=facebook/opt-125m BURST_VUS=30 BURST_ITERATIONS=30 k6 run k6/simple-auth/simple-auth-test.js
```

## Available API Keys

| User | API Key |
|------|---------|
| perftest-user1 | `perftest-user1-key` |
| perftest-user2 | `perftest-user2-key` |
| perftest-user3 | `perftest-user3-key` |
| perftest-user4 | `perftest-user4-key` |
| perftest-user5 | `perftest-user5-key` |

## Create a Baseline

Run these tests to establish performance baselines:

```bash
# Test 1: 5 users x 20 iterations (100 requests)
HOST=$HOST MODEL_NAME=facebook/opt-125m BURST_VUS=5 BURST_ITERATIONS=20 k6 run k6/simple-auth/simple-auth-test.js

# Test 2: 10 users x 20 iterations (200 requests)
HOST=$HOST MODEL_NAME=facebook/opt-125m BURST_VUS=10 BURST_ITERATIONS=20 k6 run k6/simple-auth/simple-auth-test.js

# Test 3: 20 users x 20 iterations (400 requests)
HOST=$HOST MODEL_NAME=facebook/opt-125m BURST_VUS=20 BURST_ITERATIONS=20 k6 run k6/simple-auth/simple-auth-test.js

# Test 4: 30 users x 30 iterations (900 requests)
HOST=$HOST MODEL_NAME=facebook/opt-125m BURST_VUS=30 BURST_ITERATIONS=30 k6 run k6/simple-auth/simple-auth-test.js

# Test 5: 50 users x 50 iterations (2500 requests)
HOST=$HOST MODEL_NAME=facebook/opt-125m BURST_VUS=50 BURST_ITERATIONS=50 k6 run k6/simple-auth/simple-auth-test.js

# Test 6: 100 users x 100 iterations (10000 requests)
HOST=$HOST MODEL_NAME=facebook/opt-125m BURST_VUS=100 BURST_ITERATIONS=100 k6 run k6/simple-auth/simple-auth-test.js
```

### Simple Auth Baseline Results

| Users | Iterations | Total Requests | Success Rate | Avg Response Time | Req/Sec |
|-------|------------|----------------|--------------|-------------------|---------|
| 5     | 20         | 100            | 100%         | 77ms              | ~61     |
| 10    | 20         | 200            | 100%         | 118ms             | ~28     |
| 20    | 20         | 400            | 100%         | 98ms              | ~49     |
| 30    | 30         | 900            | 100%         | 35ms              | ~130    |
| 50    | 50         | 2500           | 100%         | 78ms              | ~63     |
| 100   | 100        | 10000          | 100%         | 58ms              | ~86     |

## Cleanup

```bash
kubectl delete -k .
```

