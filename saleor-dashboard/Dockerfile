# ── Stage 1: builder ────────────────────────────────────────────────────────
FROM node:22-alpine AS builder

WORKDIR /app

# Enable corepack so pnpm is available
RUN corepack enable && corepack prepare pnpm@10.28.1 --activate

# Copy package files for dependency caching
COPY package.json pnpm-lock.yaml ./

# Install dependencies
RUN pnpm install --no-frozen-lockfile

# Copy the full source
COPY . .

# Build-time env vars — Vite bakes these into the JS bundle.
# Pass them via --build-arg in docker build or docker-compose build args.
ARG API_URL=http://localhost:8000/graphql/
ARG APP_MOUNT_URI=/
ARG STATIC_URL=/
ARG APPS_MARKETPLACE_API_URL=https://apps.saleor.io/api/v2/saleor-apps
ARG EXTENSIONS_API_URL=https://apps.saleor.io/api/v1/extensions

ENV API_URL=$API_URL
ENV APP_MOUNT_URI=$APP_MOUNT_URI
ENV STATIC_URL=$STATIC_URL
ENV APPS_MARKETPLACE_API_URL=$APPS_MARKETPLACE_API_URL
ENV EXTENSIONS_API_URL=$EXTENSIONS_API_URL

# Build the SPA — skip prebuild codegen (generated files already in repo)
RUN NODE_OPTIONS=--max-old-space-size=3072 pnpm exec vite build

# ── Stage 2: serve with nginx ────────────────────────────────────────────────
FROM nginx:alpine AS final

# Copy build output to nginx html directory
COPY --from=builder /app/build/dashboard /app/dashboard

# Copy nginx SPA config
COPY nginx/default.conf /etc/nginx/conf.d/default.conf

EXPOSE 80
