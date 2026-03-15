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

# Build-time env vars — Next.js bakes NEXT_PUBLIC_* into the bundle.
# Pass them via --build-arg in docker build or docker-compose build args.
ARG NEXT_PUBLIC_SALEOR_API_URL=http://localhost:8000/graphql/
ARG NEXT_PUBLIC_STOREFRONT_URL=http://localhost:3000
ARG NEXT_PUBLIC_DEFAULT_CHANNEL=default-channel

ENV NEXT_PUBLIC_SALEOR_API_URL=$NEXT_PUBLIC_SALEOR_API_URL
ENV NEXT_PUBLIC_STOREFRONT_URL=$NEXT_PUBLIC_STOREFRONT_URL
ENV NEXT_PUBLIC_DEFAULT_CHANNEL=$NEXT_PUBLIC_DEFAULT_CHANNEL

# Enable standalone output mode for Docker (produces a self-contained server)
ENV NEXT_OUTPUT=standalone

# During build, the layout's "use cache" components (nav, footer) try to
# call the Saleor GraphQL API to pre-populate caches. Since no backend
# is available, requests timeout and the build fails.
# Fix: start a lightweight mock GraphQL server on port 8000 so those
# prerender calls get instant empty responses and complete without timeout.
# Mock server port must match the scheme+host of NEXT_PUBLIC_SALEOR_API_URL.
# http://saleor.local/graphql/  → port 80
# http://host.docker.internal:8000/graphql/ → port 8000
# Pass MOCK_PORT as a build arg to switch between the two contexts.
ARG MOCK_PORT=80
ENV MOCK_PORT=$MOCK_PORT
RUN node -e " \
  const http = require('http'); \
  const port = parseInt(process.env.MOCK_PORT || '80'); \
  http.createServer((req, res) => { \
    let b = ''; \
    req.on('data', d => { b += d; }); \
    req.on('end', () => { \
      res.writeHead(200, {'Content-Type': 'application/json'}); \
      res.end('{\"data\":{}}'); \
    }); \
  }).listen(port, '0.0.0.0', () => process.stderr.write('Mock GraphQL ready on :' + port + '\n')); \
" & sleep 2 && pnpm exec next build

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
