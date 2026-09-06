"use strict";

const request = require("supertest");
const { createApp, safeTokenMatch } = require("../../app/createApp");

describe("HealthConnect unit tests", () => {
  const apiToken = "unit-test-token-with-sufficient-length";
  const app = createApp({ deployment: "green", version: "test-42", apiToken });

  test("constant-time token helper accepts only the exact token", () => {
    expect(safeTokenMatch(apiToken, apiToken)).toBe(true);
    expect(safeTokenMatch("incorrect", apiToken)).toBe(false);
    expect(safeTokenMatch("x".repeat(apiToken.length), apiToken)).toBe(false);
    expect(safeTokenMatch("", apiToken)).toBe(false);
  });

  test("health endpoint reports deployment and version", async () => {
    const response = await request(app).get("/health");

    expect(response.status).toBe(200);
    expect(response.body).toEqual({
      status: "healthy",
      deployment: "green",
      version: "test-42"
    });
  });

  test("root and version endpoints identify the deployed release", async () => {
    const rootResponse = await request(app).get("/");
    const versionResponse = await request(app).get("/version");

    expect(rootResponse.status).toBe(200);
    expect(rootResponse.body.message).toMatch(/HealthConnect/);
    expect(rootResponse.body.deployment).toBe("green");
    expect(versionResponse.body).toEqual({
      application: "HealthConnect",
      deployment: "green",
      version: "test-42"
    });
  });

  test("records endpoint denies a request without a token", async () => {
    const response = await request(app).get("/records");

    expect(response.status).toBe(401);
    expect(response.body).toEqual({ error: "Unauthorised" });
    expect(response.headers["cache-control"]).toBe("no-store");
  });

  test("records endpoint returns synthetic data to an authorised request", async () => {
    const response = await request(app).get("/records").set("x-api-token", apiToken);

    expect(response.status).toBe(200);
    expect(Array.isArray(response.body.records)).toBe(true);
    expect(response.body.records).toHaveLength(2);
    expect(response.body.records[0]).not.toHaveProperty("patientName");
  });

  test("unknown paths return a generic response", async () => {
    const response = await request(app).get("/private/system/path");

    expect(response.status).toBe(404);
    expect(response.body).toEqual({ error: "Not found" });
  });

  test("malformed JSON returns a generic error without implementation details", async () => {
    const errorLog = jest.spyOn(console, "error").mockImplementation(() => {});

    try {
      const response = await request(app)
        .post("/records")
        .set("content-type", "application/json")
        .send('{"broken":');

      expect(response.status).toBe(400);
      expect(response.body).toEqual({ error: "Malformed JSON" });
      expect(errorLog).toHaveBeenCalledWith("Request processing failed", { errorType: "SyntaxError" });
    } finally {
      errorLog.mockRestore();
    }
  });
});

describe("HealthConnect configuration", () => {
  test("application refuses to start without an API token", () => {
    const previousToken = process.env.HEALTHCONNECT_API_TOKEN;
    delete process.env.HEALTHCONNECT_API_TOKEN;

    try {
      expect(() => createApp({ deployment: "blue", version: "test" })).toThrow(
        "HEALTHCONNECT_API_TOKEN must be configured."
      );
    } finally {
      if (previousToken) {
        process.env.HEALTHCONNECT_API_TOKEN = previousToken;
      }
    }
  });

  test("runtime configuration is read from environment variables", async () => {
    process.env.DEPLOYMENT_COLOR = "blue";
    process.env.APP_VERSION = "environment-7";
    process.env.HEALTHCONNECT_API_TOKEN = "environment-test-token";

    try {
      const environmentApp = createApp();
      const response = await request(environmentApp).get("/version");

      expect(response.body.deployment).toBe("blue");
      expect(response.body.version).toBe("environment-7");
    } finally {
      delete process.env.DEPLOYMENT_COLOR;
      delete process.env.APP_VERSION;
      delete process.env.HEALTHCONNECT_API_TOKEN;
    }
  });

  test("safe non-production labels are used when optional labels are absent", async () => {
    const defaultLabelApp = createApp({ apiToken: "default-label-test-token" });
    const response = await request(defaultLabelApp).get("/version");

    expect(response.body.deployment).toBe("unknown");
    expect(response.body.version).toBe("development");
  });
});
