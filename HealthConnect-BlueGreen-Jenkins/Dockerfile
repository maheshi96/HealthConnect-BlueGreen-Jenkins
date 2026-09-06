# syntax=docker/dockerfile:1.7

# Install the exact dependency graph once for repeatable tests and quality gates.
FROM node:22-alpine AS dependencies
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci

# This target is built by Jenkins and fails on lint/SAST or high-risk dependencies.
FROM dependencies AS quality-gate
COPY app ./app
COPY tests ./tests
COPY eslint.config.js ./
RUN npm run lint
RUN npm run audit:dependencies

# Jenkins runs this image as an isolated unit/integration/security test runner.
FROM dependencies AS test-runner
COPY --chown=node:node app ./app
COPY --chown=node:node tests ./tests
COPY --chown=node:node eslint.config.js ./
RUN mkdir -p /app/reports && chown -R node:node /app/reports
USER node
CMD ["npm", "run", "test:unit"]

# The final image contains production dependencies and application code only.
FROM node:22-alpine AS production
ENV NODE_ENV=production \
    PORT=3000
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force
COPY --chown=node:node app ./app
USER node
EXPOSE 3000
HEALTHCHECK --interval=5s --timeout=3s --start-period=5s --retries=6 \
  CMD wget -qO- http://127.0.0.1:3000/health >/dev/null || exit 1
CMD ["node", "app/server.js"]
