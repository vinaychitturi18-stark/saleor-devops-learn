# Saleor DevOps

Mono-repo containing the Saleor e-commerce stack:

| Service | Description |
|---------|-------------|
| `saleor/` | Django/Uvicorn backend API |
| `saleor-dashboard/` | React/Vite admin dashboard |
| `saleor-storefront/` | Next.js storefront |

---

## Local Development

### Prerequisites

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) installed and running
- Add `host.docker.internal` to your Mac's `/etc/hosts` (one-time setup):
  ```bash
  echo "127.0.0.1 host.docker.internal" | sudo tee -a /etc/hosts
  ```

### 1. Build all images

```bash
docker compose build
```

> First build takes ~10–15 minutes. Subsequent builds are fast due to layer caching.

### 2. Start all services

```bash
docker compose up -d
```

### 3. Seed the database (first time only)

```bash
docker compose run --rm --entrypoint="" saleor python manage.py populatedb --createsuperuser
```

This creates sample products, channels, and an admin account.
Default credentials created: `admin@example.com` / `admin`

### 4. Access the services

| Service | URL | Credentials |
|---------|-----|-------------|
| Storefront | http://localhost:3000 | — |
| Dashboard | http://localhost:9000 | admin@example.com / admin |
| GraphQL API | http://localhost:8000/graphql/ | — |

---

## Common Commands

```bash
# Stop all containers (data is preserved in volumes)
docker compose down

# View logs for a specific service
docker compose logs saleor -f
docker compose logs storefront -f
docker compose logs dashboard -f

# Restart a single service
docker compose restart saleor

# Run a Django management command
docker compose run --rm --entrypoint="" saleor python manage.py <command>

# Open a shell inside the saleor container
docker compose exec saleor bash
```

---

## Architecture

```
Browser
  ├── localhost:3000  →  storefront (Next.js standalone)
  ├── localhost:9000  →  dashboard (nginx serving Vite SPA)
  └── localhost:8000  →  saleor API (Django + Uvicorn)

Docker internal network
  ├── saleor          →  Django API (port 8000)
  ├── worker          →  Celery worker (same image as saleor)
  ├── beat            →  Celery beat scheduler (same image as saleor)
  ├── postgres        →  PostgreSQL 15
  └── redis           →  Redis 7
```

### Networking note

`NEXT_PUBLIC_SALEOR_API_URL` is baked into the storefront bundle at build time as
`http://host.docker.internal:8000/graphql/`. This hostname resolves to your Mac from
both inside Docker containers (SSR) and the browser — which is why the `/etc/hosts`
entry above is required for local development.

---

## Troubleshooting

**Storefront shows no products**
- Check `docker compose logs storefront` for GraphQL errors
- Verify `host.docker.internal` is in `/etc/hosts`: `grep host.docker.internal /etc/hosts`

**"Checkout not found" error**
- Clear cookies for `localhost:3000` in your browser (stale checkout session)

**Saleor container keeps restarting**
- Check logs: `docker compose logs saleor`
- Usually a missing env var or migration error

**Want to reset everything (including database)**
```bash
docker compose down -v   # -v removes volumes (deletes all data)
docker compose up -d
docker compose run --rm --entrypoint="" saleor python manage.py populatedb --createsuperuser
```
