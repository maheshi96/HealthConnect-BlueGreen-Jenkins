"use strict";

const crypto = require("node:crypto");
const express = require("express");
const helmet = require("helmet");
const { rateLimit } = require("express-rate-limit");

// The lab uses synthetic records only. No genuine patient data belongs in source control.
const DEMO_RECORDS = Object.freeze([
  Object.freeze({ recordId: "HC-1001", category: "allergy", status: "active" }),
  Object.freeze({ recordId: "HC-1002", category: "immunisation", status: "current" })
]);

function safeTokenMatch(providedToken, expectedToken) {
  if (!providedToken || !expectedToken) {
    return false;
  }

  const provided = Buffer.from(providedToken);
  const expected = Buffer.from(expectedToken);

  return provided.length === expected.length && crypto.timingSafeEqual(provided, expected);
}

function createApp(options = {}) {
  const deployment = options.deployment || process.env.DEPLOYMENT_COLOR || "unknown";
  const version = options.version || process.env.APP_VERSION || "development";
  const apiToken = options.apiToken || process.env.HEALTHCONNECT_API_TOKEN;

  if (!apiToken) {
    throw new Error("HEALTHCONNECT_API_TOKEN must be configured.");
  }

  const app = express();
  app.disable("x-powered-by");
  app.use(helmet());
  app.use(express.json({ limit: "16kb" }));

  // Health and version endpoints reveal operational state, but no patient information.
  app.get("/", (_request, response) => {
    response.set("Cache-Control", "no-store");
    response.status(200).json({
      message: "HealthConnect patient portal is available.",
      deployment,
      version
    });
  });

  app.get("/health", (_request, response) => {
    response.set("Cache-Control", "no-store");
    response.status(200).json({ status: "healthy", deployment, version });
  });

  app.get("/version", (_request, response) => {
    response.set("Cache-Control", "no-store");
    response.status(200).json({ application: "HealthConnect", deployment, version });
  });

  const recordsLimiter = rateLimit({
    windowMs: 60_000,
    limit: 60,
    standardHeaders: "draft-8",
    legacyHeaders: false,
    message: { error: "Too many requests. Try again shortly." }
  });

  app.get("/records", recordsLimiter, (request, response) => {
    const providedToken = request.get("x-api-token") || "";

    if (!safeTokenMatch(providedToken, apiToken)) {
      response.set("Cache-Control", "no-store");
      return response.status(401).json({ error: "Unauthorised" });
    }

    response.set("Cache-Control", "no-store");
    return response.status(200).json({ records: DEMO_RECORDS });
  });

  app.use((_request, response) => {
    response.set("Cache-Control", "no-store");
    response.status(404).json({ error: "Not found" });
  });

  // Return a generic message so stack traces and internal details are not exposed.
  app.use((error, _request, response, _next) => {
    console.error("Request processing failed", { errorType: error.name });
    response.set("Cache-Control", "no-store");

    if (error.type === "entity.too.large") {
      return response.status(413).json({ error: "Request body too large" });
    }

    if (error.type === "entity.parse.failed") {
      return response.status(400).json({ error: "Malformed JSON" });
    }

    response.status(500).json({ error: "Internal server error" });
  });

  return app;
}

module.exports = { createApp, safeTokenMatch };
