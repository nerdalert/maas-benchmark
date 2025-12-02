import http from "k6/http";
import { check } from "k6";

// Load a single token for testing
const tokens = JSON.parse(open("tokens/all/all_tokens.json"));
const testToken = tokens.free[0];

export const options = {
  vus: 1,
  iterations: 1,
  httpDebug: "full", // Enable full HTTP debugging
};

export default function () {
  // Use HTTP instead of HTTPS - same as working curl command
  const fullUrl = "http://maas.apps.rosa.ff3tg-kstb8-p3q.c8bp.p3.openshiftapps.com/llm/facebook-opt-125m-simulated/v1/chat/completions";
  const payload = JSON.stringify({
    model: "facebook/opt-125m",
    prompt: "Hello",
    max_tokens: 50
  });

  const params = {
    headers: {
      "Authorization": `Bearer ${testToken.token}`,
      "Content-Type": "application/json",
    },
    timeout: "10s",
  };

  console.log("Making POST request to:", fullUrl);
  console.log("Using token from user:", testToken.user_id);

  const response = http.post(fullUrl, payload, params);

  console.log(`Response status: ${response.status}`);
  console.log(`Response time: ${response.timings.duration}ms`);
  console.log(`HTTP version: ${response.proto}`);

  if (response.status !== 200) {
    console.log(`Response body: ${response.body ? response.body.substring(0, 200) : 'No response body'}`);
  }

  check(response, {
    "status is 200": (r) => r.status === 200,
    "response time < 15s": (r) => r.timings.duration < 15000,
  });
}