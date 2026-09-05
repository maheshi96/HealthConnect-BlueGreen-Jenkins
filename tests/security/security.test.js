"use strict";

const axios = require("axios");

const targetUrl = process.env.TARGET_URL;

if (!targetUrl) {
  throw new Error("TARGET_URL is required for security tests.");
}

const client = axios.create({ baseURL: targetUrl, timeout: 5_000, validateStatus: () => true });

describe("HealthConnect security controls", () => {
  test("security headers are enabled and framework details are hidden", async () => {
    const response = await client.get("/");

    expect(response.status).toBe(200);
    expect(response.headers).toHaveProperty("content-security-policy");
    expect(response.headers).toHaveProperty("x-content-type-options", "nosniff");
    expect(response.headers).toHaveProperty("x-frame-options", "SAMEORIGIN");
    expect(response.headers).not.toHaveProperty("x-powered-by");
  });

  test("patient-record responses cannot be cached", async () => {
    const response = await client.get("/records");

    expect(response.status).toBe(401);
    expect(response.headers["cache-control"]).toBe("no-store");
  });

  test("malformed and oversized input is rejected without a stack trace", async () => {
    const response = await client.post("/records", "{".repeat(20_000), {
      headers: { "content-type": "application/json" }
    });

    expect([404, 413]).toContain(response.status);
    expect(JSON.stringify(response.data)).not.toMatch(/node_modules|createApp\.js|stack/i);
  });
});
