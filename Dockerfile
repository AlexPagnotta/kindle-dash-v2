# Must match the "playwright" version in package.json, the browsers are baked into this image
ARG PLAYWRIGHT_VERSION=1.63.0

FROM mcr.microsoft.com/playwright:v${PLAYWRIGHT_VERSION}-noble AS base
WORKDIR /app
ENV NEXT_TELEMETRY_DISABLED=1

FROM base AS deps
COPY package.json package-lock.json ./
RUN npm ci

FROM base AS builder
COPY --from=deps /app/node_modules ./node_modules
COPY . .
RUN npm run build

FROM base AS runner
ENV NODE_ENV=production \
    HOSTNAME=0.0.0.0 \
    PORT=3000 \
    DASH_CACHE_DIR=/tmp/kindle-dash

COPY --from=builder /app/public ./public
COPY --from=builder /app/.next/standalone ./
COPY --from=builder /app/.next/static ./.next/static
# Standalone tracing keeps Playwright's JS but drops its data files, so ship those packages whole
COPY --from=deps /app/node_modules/playwright ./node_modules/playwright
COPY --from=deps /app/node_modules/playwright-core ./node_modules/playwright-core

USER pwuser
EXPOSE 3000
CMD ["node", "server.js"]
