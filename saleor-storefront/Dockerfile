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
ARG NEXT_PUBLIC_SALEOR_API_URL=https://learnwithvinay.in/graphql/
ARG NEXT_PUBLIC_STOREFRONT_URL=https://learnwithvinay.in
ARG NEXT_PUBLIC_DEFAULT_CHANNEL=default-channel

ENV NEXT_PUBLIC_SALEOR_API_URL=$NEXT_PUBLIC_SALEOR_API_URL
ENV NEXT_PUBLIC_STOREFRONT_URL=$NEXT_PUBLIC_STOREFRONT_URL
ENV NEXT_PUBLIC_DEFAULT_CHANNEL=$NEXT_PUBLIC_DEFAULT_CHANNEL

# Enable standalone output mode for Docker (produces a self-contained server)
ENV NEXT_OUTPUT=standalone

RUN pnpm exec next build

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
