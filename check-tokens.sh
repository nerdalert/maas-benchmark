#!/bin/bash

now=$(date +%s)
echo "Current time: $(date)"
echo "Current timestamp: $now"
echo ""

for f in tokens/free/*.json; do
    echo "=== $(basename $f) ==="
    token=$(jq -r '.token' "$f")
    exp=$(echo "$token" | cut -d'.' -f2 | base64 -d 2>/dev/null | jq -r '.exp' 2>/dev/null)

    if [ -n "$exp" ]; then
        echo "Expires at: $(date -d @$exp 2>/dev/null || echo $exp)"
        if [ $exp -lt $now ]; then
            echo "STATUS: EXPIRED ❌"
        else
            remaining=$((exp - now))
            echo "STATUS: Valid ✓ (${remaining}s remaining)"
        fi
    else
        echo "STATUS: Cannot read expiration"
    fi
    echo ""
done
