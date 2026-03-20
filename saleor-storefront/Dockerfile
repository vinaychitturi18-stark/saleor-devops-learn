# ── Stage 1: deps ───────────────────────────────────────────────────────────
FROM node:20-alpine AS deps

WORKDIR /app

RUN corepack enable && corepack prepare pnpm@10.28.1 --activate

COPY package.json pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile

# ── Stage 2: builder ─────────────────────────────────────────────────────────
FROM node:20-alpine AS builder

WORKDIR /app

RUN corepack enable && corepack prepare pnpm@10.28.1 --activate

# Copy installed node_modules from deps stage
COPY --from=deps /app/node_modules ./node_modules

# Copy full source
COPY . .

# Real build-time env vars — passed via --build-arg
ARG NEXT_PUBLIC_SALEOR_API_URL=https://dev.learnwithvinay.in/graphql/
ARG NEXT_PUBLIC_STOREFRONT_URL=http://localhost:3000
ARG NEXT_PUBLIC_DEFAULT_CHANNEL=default-channel

# Store real URL for post-build patching
ENV REAL_API_URL=$NEXT_PUBLIC_SALEOR_API_URL
ENV NEXT_PUBLIC_STOREFRONT_URL=$NEXT_PUBLIC_STOREFRONT_URL
ENV NEXT_PUBLIC_DEFAULT_CHANNEL=$NEXT_PUBLIC_DEFAULT_CHANNEL

# Enable standalone output mode for Docker (produces a self-contained server)
ENV NEXT_OUTPUT=standalone

# During build, "use cache" components try to call the GraphQL API to pre-populate
# caches. If the URL resolves (even with 503), Next.js retries and eventually
# times out with USE_CACHE_TIMEOUT. If the URL does NOT resolve (ENOTFOUND),
# Next.js fails fast and handles it gracefully.
# Fix: build with a placeholder URL that won't resolve, then patch the real URL
# into the JS bundle after build.
ENV NEXT_PUBLIC_SALEOR_API_URL=https://saleor-build-placeholder.invalid/graphql/
RUN pnpm exec next build && \
    find .next -type f -name "*.js" \
      -exec sed -i "s|https://saleor-build-placeholder.invalid/graphql/|${REAL_API_URL}|g" {} +

# ── Stage 3: final ────────────────────────────────────────────────────────────
FROM node:20-alpine AS final

WORKDIR /app

ENV NODE_ENV=production

# Copy the standalone server bundle
COPY --from=builder /app/.next/standalone ./

# Copy static assets (CSS, JS chunks) into the expected location
COPY --from=builder /app/.next/static ./.next/static

# Copy public assets (images, fonts, etc.)
COPY --from=builder /app/public ./public

EXPOSE 3000

ENV PORT=3000
ENV HOSTNAME=0.0.0.0

CMD ["node", "server.js"]
