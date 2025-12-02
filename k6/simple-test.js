import http from "k6/http";
import { check, sleep } from "k6";

// Simple test script for quick validation
// Usage: k6 run -e HOST=maas.your-cluster.com -e TOKEN=your-token simple-test.js

const HOST = __ENV.HOST || "maas.example.com";
const PROTOCOL = __ENV.PROTOCOL || "https";
const TOKEN = __ENV.TOKEN || "";
const MODEL_NAME = __ENV.MODEL_NAME || "test-model";

export const options = {
    vus: 1,
    duration: "30s",
};

export default function () {
    if (!TOKEN) {
        console.error("TOKEN environment variable is required");
        return;
    }

    const modelUrl = `${PROTOCOL}://${HOST}/llm/${MODEL_NAME}/v1/chat/completions`;

    const payload = JSON.stringify({
        model: MODEL_NAME,
        messages: [{ role: "user", content: "Hello, this is a simple test" }],
        max_tokens: 50
    });

    const headers = {
        "Authorization": `Bearer ${TOKEN}`,
        "Content-Type": "application/json"
    };

    const response = http.post(modelUrl, payload, { headers });

    check(response, {
        "status is 2xx": (r) => r.status >= 200 && r.status < 300,
        "response time < 10s": (r) => r.timings.duration < 10000,
        "has response body": (r) => r.body.length > 0,
    });

    if (response.status !== 200) {
        console.log(`Request failed with status ${response.status}: ${response.body}`);
    }

    sleep(1);
}