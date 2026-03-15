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

---

## Kubernetes Deployment (Local Cluster via Multipass)

A production-like setup running on a 2-node Kubernetes cluster on your Mac using Multipass VMs.

### Architecture

```
Browser
  └── http://saleor.local:8080/
        ├── /graphql/    → saleor backend (Django, port 8000)
        ├── /static/     → saleor backend
        ├── /media/      → saleor backend
        ├── /dashboard/  → dashboard (nginx SPA, port 80)
        └── /            → storefront (Next.js, port 3000)

Kubernetes cluster (Multipass VMs)
  ├── controlplane  192.168.2.3  (master node)
  └── node01        192.168.2.2  (worker node)
```

### Access URLs

| Service    | URL                                 |
|------------|-------------------------------------|
| Storefront | http://saleor.local:8080/           |
| Dashboard  | http://saleor.local:8080/dashboard/ |
| GraphQL    | http://saleor.local:8080/graphql/   |

**Dashboard login:** `admin@example.com` / `admin`

---

### Day-to-day (after every Mac restart)

```bash
# 1. Start the VMs
multipass start controlplane node01

# 2. Fix kubeconfig (only if VM IPs changed after restart)
multipass exec controlplane -- sudo cat /etc/kubernetes/admin.conf \
  | sed "s|https://.*:6443|https://192.168.2.3:6443|g" \
  > ~/.kube/saleor-k8s.conf

# 3. Start the port-forward tunnel
./k8s/forward.sh start
```

To stop everything:
```bash
./k8s/forward.sh stop
multipass stop controlplane node01
```

---

### Full Deployment Guide (from scratch)

#### Prerequisites

- [Multipass](https://multipass.run/) installed
- [Docker Desktop](https://www.docker.com/products/docker-desktop/) running
- `kubectl` installed (`brew install kubectl`)

---

#### Step 1 — Start VMs

```bash
multipass start controlplane node01

# Verify both show "Running"
multipass list
```

---

#### Step 2 — Configure kubectl

```bash
CONTROL_IP=192.168.2.3

multipass exec controlplane -- sudo cat /etc/kubernetes/admin.conf \
  | sed "s|https://.*:6443|https://${CONTROL_IP}:6443|g" \
  > ~/.kube/saleor-k8s.conf

export KUBECONFIG=~/.kube/saleor-k8s.conf

# Should show both nodes as Ready
kubectl get nodes
```

---

#### Step 3 — Build & Push Docker Images

> Skip this step if images are already on Docker Hub and code hasn't changed.

```bash
docker login   # login as vinaylearnerman

# Saleor backend
docker build -t vinaylearnerman/saleor-backend:latest ./saleor
docker push vinaylearnerman/saleor-backend:latest

# Dashboard
docker build \
  --build-arg API_URL=http://saleor.local:8080/graphql/ \
  --build-arg APP_MOUNT_URI=/dashboard/ \
  --build-arg STATIC_URL=/dashboard/ \
  -t vinaylearnerman/saleor-dashboard:latest ./saleor-dashboard
docker push vinaylearnerman/saleor-dashboard:latest

# Storefront
docker build \
  --add-host=saleor.local:127.0.0.1 \
  --build-arg NEXT_PUBLIC_SALEOR_API_URL=http://saleor.local:8080/graphql/ \
  --build-arg NEXT_PUBLIC_STOREFRONT_URL=http://saleor.local:8080 \
  --build-arg NEXT_PUBLIC_DEFAULT_CHANNEL=default-channel \
  --build-arg MOCK_PORT=8080 \
  -t vinaylearnerman/saleor-storefront:latest ./saleor-storefront
docker push vinaylearnerman/saleor-storefront:latest
```

---

#### Step 4 — Install nginx Ingress Controller (one-time)

```bash
export KUBECONFIG=~/.kube/saleor-k8s.conf

kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.11.3/deploy/static/provider/baremetal/deploy.yaml

kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s
```

---

#### Step 5 — Deploy Everything

```bash
export KUBECONFIG=~/.kube/saleor-k8s.conf

./k8s/deploy.sh vinaylearnerman
```

This script applies all manifests in order and waits for postgres and saleor to be ready.

---

#### Step 6 — First-Time Database Setup (one-time only)

```bash
export KUBECONFIG=~/.kube/saleor-k8s.conf

# Run migrations
kubectl exec -n saleor deploy/saleor -- python manage.py migrate

# Create admin user
kubectl exec -n saleor deploy/saleor -- \
  python manage.py createsuperuser \
  --email admin@example.com --noinput
kubectl exec -n saleor deploy/saleor -- \
  python manage.py changepassword admin@example.com

# Load sample product data
kubectl exec -n saleor deploy/saleor -- python manage.py populatedb
```

---

#### Step 7 — Add hosts entry (one-time)

```bash
echo "127.0.0.1 saleor.local" | sudo tee -a /etc/hosts
```

---

#### Step 8 — Start & access

```bash
./k8s/forward.sh start
```

Open http://saleor.local:8080/ in your browser.

---

### Kubernetes Manifests

```
k8s/
├── 00-namespace.yaml    # saleor namespace
├── 01-secrets.yaml      # passwords (base64 encoded)
├── 02-configmap.yaml    # app config (env vars)
├── 03-postgres.yaml     # database deployment + PVC
├── 04-redis.yaml        # cache / task queue
├── 05-media-pvc.yaml    # persistent volume for uploaded images
├── 06-saleor.yaml       # Django API deployment
├── 07-worker.yaml       # Celery worker
├── 08-beat.yaml         # Celery scheduler
├── 09-dashboard.yaml    # Admin SPA deployment
├── 10-storefront.yaml   # Next.js storefront deployment
├── 11-ingress.yaml      # nginx Ingress routing rules
├── deploy.sh            # applies all manifests in one command
└── forward.sh           # starts the port-forward tunnel
```

---

### Kubernetes Troubleshooting

**kubectl can't connect after VM restart**
The VM IP may have changed. Re-run Step 2 with the new IP from `multipass list`.

**Port-forward dies**
```bash
./k8s/forward.sh stop
./k8s/forward.sh start
```

**Check pod status**
```bash
export KUBECONFIG=~/.kube/saleor-k8s.conf
kubectl get pods -n saleor
kubectl logs -n saleor deploy/saleor
```

**Force pull latest image after a rebuild**
```bash
export KUBECONFIG=~/.kube/saleor-k8s.conf
kubectl rollout restart deployment/<name> -n saleor
```
