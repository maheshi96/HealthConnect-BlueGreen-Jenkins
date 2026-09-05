"use strict";

const axios = require("axios");

const targetUrl = process.env.TARGET_URL;
const expectedDeployment = process.env.EXPECTED_DEPLOYMENT;
const expectedVersion = process.env.EXPECTED_VERSION;
const apiToken = process.env.HEALTHCONNECT_API_TOKEN;

if (!targetUrl || !expectedDeployment || !expectedVersion || !apiToken) {
  throw new Error("TARGET_URL, EXPECTED_DEPLOYMENT, EXPECTED_VERSION and HEALTHCONNECT_API_TOKEN are required.");
}

const client = axios.create({ baseURL: targetUrl, timeout: 5_000, validateStatus: () => true });

describe("idle-environment integration tests", () => {
  test("health endpoint identifies the candidate environment", async () => {
    const response = await client.get("/health");

    expect(response.status).toBe(200);
    expect(response.data.status).toBe("healthy");
    expect(response.data.deployment).toBe(expectedDeployment);
    expect(response.data.version).toBe(expectedVersion);
  });

  test("version endpoint identifies the immutable build", async () => {
    const response = await client.get("/version");

    expect(response.status).toBe(200);
    expect(response.data.application).toBe("HealthConnect");
    expect(response.data.deployment).toBe(expectedDeployment);
    expect(response.data.version).toBe(expectedVersion);
  });

  test("medical records require authentication", async () => {
    const denied = await client.get("/records");
    const allowed = await client.get("/records", { headers: { "x-api-token": apiToken } });

    expect(denied.status).toBe(401);
    expect(allowed.status).toBe(200);
    expect(Array.isArray(allowed.data.records)).toBe(true);
  });
});
