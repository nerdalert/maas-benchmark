/*
 * Simple Auth Performance Test
 * Tests API key authentication baseline (no TokenReview/SubjectAccessReview)
 *
 * Example usage:
 *   # Single request debug test
 *   HOST=$HOST MODEL_NAME=facebook/opt-125m BURST_VUS=1 BURST_ITERATIONS=1 DEBUG=true k6 run k6/simple-auth/simple-auth-test.js
 *
 *   # 5 users, 20 requests each (100 total)
 *   HOST=$HOST MODEL_NAME=facebook/opt-125m BURST_VUS=5 BURST_ITERATIONS=20 k6 run k6/simple-auth/simple-auth-test.js
 *
 *   # 20 users, 20 requests each (400 total)
 *   HOST=$HOST MODEL_NAME=facebook/opt-125m BURST_VUS=20 BURST_ITERATIONS=20 k6 run k6/simple-auth/simple-auth-test.js
 *
 *   # 30 concurrent users, 1 request each
 *   HOST=$HOST MODEL_NAME=facebook/opt-125m BURST_VUS=30 BURST_ITERATIONS=1 k6 run k6/simple-auth/simple-auth-test.js
 *
 *   # 30 concurrent users, 30 requests each (900 total)
 *   HOST=$HOST MODEL_NAME=facebook/opt-125m BURST_VUS=30 BURST_ITERATIONS=30 k6 run k6/simple-auth/simple-auth-test.js
 */

import http from "k6/http";
import { check } from "k6";
import { Counter, Rate, Trend } from "k6/metrics";

// Configuration
const HOST = __ENV.HOST || "";
const MODEL_NAME = __ENV.MODEL_NAME || "facebook/opt-125m";
const BURST_VUS = Number(__ENV.BURST_VUS || 5);
const BURST_ITERATIONS = Number(__ENV.BURST_ITERATIONS || 5);
const REQUEST_TIMEOUT = __ENV.REQUEST_TIMEOUT || "30s";

// API Keys for simple auth testing
const API_KEYS = [
    { user_id: "perftest-user1", token: "perftest-user1-key" },
    { user_id: "perftest-user2", token: "perftest-user2-key" },
    { user_id: "perftest-user3", token: "perftest-user3-key" },
    { user_id: "perftest-user4", token: "perftest-user4-key" },
    { user_id: "perftest-user5", token: "perftest-user5-key" },
];

// Metrics
const authFailures = new Counter("auth_failures");
const successRate = new Rate("success_rate");
const responseTimeTrend = new Trend("response_time", true);

export const options = {
    scenarios: {
        simple_auth_burst: {
            executor: "shared-iterations",
            vus: Math.min(BURST_VUS, API_KEYS.length),
            iterations: BURST_ITERATIONS,
            maxDuration: "5m"
        }
    },
    thresholds: {
        http_req_duration: ["p(95)<5000"],
        http_req_failed: ["rate<0.1"],
        success_rate: ["rate>0.9"],
    },
};

function getRandomApiKey() {
    return API_KEYS[Math.floor(Math.random() * API_KEYS.length)];
}

function buildModelUrl() {
    const urlModelName = MODEL_NAME.replace(/\//g, "-") + "-simulated";
    return `http://${HOST}/simple/llm/${urlModelName}/v1/completions`;
}

export default function() {
    const apiKey = getRandomApiKey();
    const modelUrl = buildModelUrl();

    const payload = JSON.stringify({
        model: MODEL_NAME,
        prompt: `Test request from ${apiKey.user_id}`,
        max_tokens: 50
    });

    const headers = {
        "Authorization": `APIKEY ${apiKey.token}`,
        "Content-Type": "application/json"
    };

    const response = http.post(modelUrl, payload, {
        headers,
        timeout: REQUEST_TIMEOUT
    });

    responseTimeTrend.add(response.timings.duration);

    const success = response.status >= 200 && response.status < 400;
    successRate.add(success);

    if (response.status === 401 || response.status === 403) {
        authFailures.add(1);
    }

    check(response, {
        "status_success": (r) => r.status >= 200 && r.status < 400,
        "response_time_ok": (r) => r.timings.duration < 30000,
    });

    if (__ENV.DEBUG === "true") {
        console.log(`[${apiKey.user_id}] Status ${response.status}, URL: ${modelUrl}`);
        if (response.status !== 200) {
            console.log(`Response: ${response.body.substring(0, 200)}`);
        }
    }
}

export function setup() {
    console.log("=== Simple Auth Performance Test ===");
    console.log(`Host: ${HOST}`);
    console.log(`Model: ${MODEL_NAME}`);
    console.log(`VUs: ${BURST_VUS}`);
    console.log(`Iterations: ${BURST_ITERATIONS}`);
    console.log(`Model URL: ${buildModelUrl()}`);
    console.log("=====================================");
}

export function teardown() {
    console.log("=== Simple Auth Test Complete ===");
}
