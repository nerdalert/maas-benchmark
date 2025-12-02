#!/bin/bash
set -euo pipefail

CLUSTER_DOMAIN=$(kubectl get ingresses.config.openshift.io cluster -o jsonpath='{.spec.domain}' 2>/dev/null)
TOKEN=$(jq -r '.token' tokens/free/benchuser-free-1.json)

echo "Testing token for benchuser-free-1..."
echo "URL: https://maas.${CLUSTER_DOMAIN}/llm/facebook-opt-125m-simulated/v1/chat/completions"
echo ""

curl -sk -w "\nHTTP Status: %{http_code}\n" -X POST \
    "https://maas.${CLUSTER_DOMAIN}/llm/facebook-opt-125m-simulated/v1/chat/completions" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"model": "facebook/opt-125m", "prompt": "test", "max_tokens": 5}'

echo ""
