#!/bin/bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Configuration
FREE_USERS=${FREE_USERS:-3}
PREMIUM_USERS=${PREMIUM_USERS:-3}
CLEAN_TOKENS=${CLEAN_TOKENS:-true}

log_info "Starting cleanup of test users and resources..."

# Get tier group mappings
FREE_GROUP=$(kubectl get configmap tier-to-group-mapping -n maas-api -o jsonpath='{.data.free}' 2>/dev/null || echo "")
PREMIUM_GROUP=$(kubectl get configmap tier-to-group-mapping -n maas-api -o jsonpath='{.data.premium}' 2>/dev/null || echo "")

# Clean up service accounts created by MaaS API
log_info "Cleaning up service accounts in tier namespaces..."

# Free tier service accounts
FREE_NAMESPACE="maas-default-gateway-tier-free"
if kubectl get namespace "$FREE_NAMESPACE" &>/dev/null; then
    log_info "Cleaning up service accounts in $FREE_NAMESPACE..."
    for i in $(seq 1 $FREE_USERS); do
        username="freeuser${i}"
        # MaaS API creates service accounts with username hash pattern
        # Find SAs that might belong to this user
        kubectl get sa -n "$FREE_NAMESPACE" -o json | \
            jq -r '.items[] | select(.metadata.name | contains("cluster-admin")) | .metadata.name' | \
            while read sa_name; do
                log_info "Deleting service account: $FREE_NAMESPACE/$sa_name"
                kubectl delete sa "$sa_name" -n "$FREE_NAMESPACE" --ignore-not-found=true 2>/dev/null || true
            done
    done
fi

# Premium tier service accounts
PREMIUM_NAMESPACE="maas-default-gateway-tier-premium"
if kubectl get namespace "$PREMIUM_NAMESPACE" &>/dev/null; then
    log_info "Cleaning up service accounts in $PREMIUM_NAMESPACE..."
    for i in $(seq 1 $PREMIUM_USERS); do
        username="premiumuser${i}"
        kubectl get sa -n "$PREMIUM_NAMESPACE" -o json | \
            jq -r '.items[] | select(.metadata.name | contains("cluster-admin")) | .metadata.name' | \
            while read sa_name; do
                log_info "Deleting service account: $PREMIUM_NAMESPACE/$sa_name"
                kubectl delete sa "$sa_name" -n "$PREMIUM_NAMESPACE" --ignore-not-found=true 2>/dev/null || true
            done
    done
fi

# Remove users from groups
log_info "Removing users from groups..."

if [ -n "$FREE_GROUP" ]; then
    for i in $(seq 1 $FREE_USERS); do
        username="freeuser${i}"
        log_info "Removing $username from $FREE_GROUP"
        oc adm groups remove-users "$FREE_GROUP" "$username" 2>/dev/null || true
    done
fi

if [ -n "$PREMIUM_GROUP" ]; then
    for i in $(seq 1 $PREMIUM_USERS); do
        username="premiumuser${i}"
        log_info "Removing $username from $PREMIUM_GROUP"
        oc adm groups remove-users "$PREMIUM_GROUP" "$username" 2>/dev/null || true
    done
fi

# Delete groups if they're now empty and were created for testing
# Note: We only delete if ALL members are test users
if [ -n "$FREE_GROUP" ]; then
    group_members=$(oc get group "$FREE_GROUP" -o jsonpath='{.users}' 2>/dev/null || echo "")
    if [ -z "$group_members" ] || [ "$group_members" == "[]" ]; then
        log_info "Group $FREE_GROUP is empty, considering for deletion"
        # Only delete if it looks like a test group (contains 'test' or 'benchmark')
        if [[ "$FREE_GROUP" =~ test|benchmark ]]; then
            log_info "Deleting empty test group: $FREE_GROUP"
            oc delete group "$FREE_GROUP" 2>/dev/null || true
        fi
    fi
fi

if [ -n "$PREMIUM_GROUP" ]; then
    group_members=$(oc get group "$PREMIUM_GROUP" -o jsonpath='{.users}' 2>/dev/null || echo "")
    if [ -z "$group_members" ] || [ "$group_members" == "[]" ]; then
        log_info "Group $PREMIUM_GROUP is empty, considering for deletion"
        if [[ "$PREMIUM_GROUP" =~ test|benchmark ]]; then
            log_info "Deleting empty test group: $PREMIUM_GROUP"
            oc delete group "$PREMIUM_GROUP" 2>/dev/null || true
        fi
    fi
fi

# Remove htpasswd identity provider
log_info "Removing htpasswd identity provider from OAuth..."
cat <<EOF | oc apply -f -
apiVersion: config.openshift.io/v1
kind: OAuth
metadata:
  name: cluster
spec:
  identityProviders: []
EOF

# Delete htpasswd secret
log_info "Deleting htpasswd secret..."
oc delete secret htpasswd-secret -n openshift-config --ignore-not-found=true 2>/dev/null || true

# Delete identities
log_info "Cleaning up user identities..."
for i in $(seq 1 $FREE_USERS); do
    username="freeuser${i}"
    oc delete identity "htpasswd_provider:$username" --ignore-not-found=true 2>/dev/null || true
    oc delete user "$username" --ignore-not-found=true 2>/dev/null || true
done

for i in $(seq 1 $PREMIUM_USERS); do
    username="premiumuser${i}"
    oc delete identity "htpasswd_provider:$username" --ignore-not-found=true 2>/dev/null || true
    oc delete user "$username" --ignore-not-found=true 2>/dev/null || true
done

# Clean up token files if requested
if [ "$CLEAN_TOKENS" == "true" ]; then
    log_info "Cleaning up token files..."
    rm -rf tokens/free/*.json tokens/premium/*.json tokens/all/*.json 2>/dev/null || true
    log_info "Token files removed"
fi

log_info "Waiting for OAuth pods to restart..."
sleep 5

log_info "Cleanup complete!"
echo ""
log_info "Summary:"
echo "  - Removed $FREE_USERS free tier users"
echo "  - Removed $PREMIUM_USERS premium tier users"
echo "  - Removed htpasswd identity provider"
echo "  - Cleaned up service accounts"
if [ "$CLEAN_TOKENS" == "true" ]; then
    echo "  - Removed token files"
fi
echo ""
log_warn "Note: OAuth pods will restart automatically. This may take 1-2 minutes."
