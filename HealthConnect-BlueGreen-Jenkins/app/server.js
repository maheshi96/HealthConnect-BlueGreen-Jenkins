"use strict";

const { createApp } = require("./createApp");

const port = Number.parseInt(process.env.PORT || "3000", 10);
const app = createApp();

const server = app.listen(port, "0.0.0.0", () => {
  console.log("HealthConnect started", {
    port,
    deployment: process.env.DEPLOYMENT_COLOR || "unknown",
    version: process.env.APP_VERSION || "development"
  });
});

function shutdown(signal) {
  console.log("HealthConnect shutting down", { signal });
  server.close(() => process.exit(0));
  setTimeout(() => process.exit(1), 10_000).unref();
}

process.on("SIGTERM", () => shutdown("SIGTERM"));
process.on("SIGINT", () => shutdown("SIGINT"));
