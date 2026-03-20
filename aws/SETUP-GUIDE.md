# Saleor AWS ECS Deployment Guide

Everything learned from the dev setup — mistakes, fixes, and steps to follow for any environment.

---

## 1. Docker Image Builds

### Backend (Saleor API)

```bash
docker build --platform linux/arm64 -t saleor-backend:latest ./saleor/
```

- No build arguments needed
- Uses `entrypoint.sh` which runs migrations + collectstatic + uvicorn on start
- The entrypoint has a case statement: `worker)` starts Celery, `beat)` starts Celery beat, `*)` runs the default server

### Dashboard

```bash
docker build --platform linux/arm64 \
  --build-arg API_URL=https://<YOUR_DOMAIN>/graphql/ \
  --build-arg APP_MOUNT_URI=/dashboard/ \
  --build-arg STATIC_URL=/dashboard/ \
  -t saleor-dashboard:latest ./saleor-dashboard/
```

**CRITICAL: `APP_MOUNT_URI` and `STATIC_URL` must be `/dashboard/`**

Without this, the dashboard's JS/CSS files are served at root `/` paths (like `/index-DF7BwP0j.js`). The ALB routes `/` to the storefront, so the dashboard's assets get 404. Setting `STATIC_URL=/dashboard/` ensures assets are at `/dashboard/index-DF7BwP0j.js` which the ALB correctly routes to the dashboard service.

### Storefront

```bash
docker build --platform linux/arm64 \
  --build-arg NEXT_PUBLIC_SALEOR_API_URL=https://<YOUR_DOMAIN>/graphql/ \
  -t saleor-storefront:latest ./saleor-storefront/
```

### Push to ECR

```bash
# Login to ECR
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin <ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com

# Tag and push each image
docker tag saleor-backend:latest <ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/saleor-backend:latest
docker push <ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/saleor-backend:latest

docker tag saleor-dashboard:latest <ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/saleor-dashboard:latest
docker push <ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/saleor-dashboard:latest

docker tag saleor-storefront:latest <ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/saleor-storefront:latest
docker push <ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/saleor-storefront:latest
```

### ARM64 vs x86_64

We use `--platform linux/arm64` because:
- Mac M1/M2 natively builds ARM64 images (fast)
- ECS Fargate supports ARM64 via AWS Graviton processors (cheaper)
- Building `linux/amd64` on Mac uses QEMU emulation which breaks Node.js builds (injects `--no-opt` flag)
- Real companies use CI/CD (GitHub Actions on Linux runners) to avoid this issue

---

## 2. AWS Resources Setup Order

Create in this order (each depends on the previous):

1. **ECR repositories** — push Docker images first
2. **VPC + Subnets** — networking foundation
3. **Internet Gateway** — attach to VPC for public subnets
4. **NAT Gateway** — in public subnet, so private subnets can reach internet
5. **Route tables** — public subnets → IGW, private subnets → NAT
6. **Security Groups** — ALB, ECS, RDS, Redis (see section below)
7. **RDS PostgreSQL** — in private subnets
8. **ElastiCache Redis** — in private subnets (**cluster mode DISABLED** — see gotcha #1)
9. **Secrets Manager** — store DATABASE_URL, CELERY_BROKER_URL, etc.
10. **S3 bucket** — for media/product images (ACLs enabled, public read)
11. **IAM role** — `ecsTaskRole` with policies (see section below)
12. **CloudWatch log groups** — one per service
13. **ACM certificate** — for HTTPS on ALB
14. **ALB + Target Groups** — with path-based routing rules
15. **ECS Cluster + Task Definitions + Services**
16. **Route 53** — DNS pointing to ALB
17. **Run management tasks** — migrate, populatedb, create admin, set site domain

---

## 3. Security Groups

| SG Name | Inbound Rules |
|---------|--------------|
| `alb-sg` | Port 80, 443 from `0.0.0.0/0` (or your IP for dev) |
| `ecs-sg` | Port 8000, 80, 3000 from `alb-sg` |
| `rds-sg` | Port 5432 from `ecs-sg` |
| `redis-sg` | Port 6379 from `ecs-sg` |

---

## 4. IAM Role (`ecsTaskRole`)

Attach these policies:
- `AmazonECSTaskExecutionRolePolicy` — pull images from ECR, write logs
- `CloudWatchLogsFullAccess` — write container logs
- `SecretsManagerReadWrite` — read secrets for env vars
- `AmazonS3FullAccess` — upload/read media files

The same role is used for both `executionRoleArn` (ECS agent operations) and `taskRoleArn` (app-level AWS access like S3).

---

## 5. ALB Routing Rules

| Priority | Path Pattern | Target Group | Why |
|----------|-------------|--------------|-----|
| 1 | `/graphql/*` | backend (port 8000) | API requests |
| 2 | `/dashboard/*` | dashboard (port 80) | Admin panel |
| 3 | `/thumbnail/*` | backend (port 8000) | Product image thumbnails |
| 4 | `/media/*` | backend (port 8000) | Media file serving |
| default | `/*` | storefront (port 3000) | Customer-facing shop |

**Without rules 3 and 4**, thumbnail and media requests go to the storefront (default) which returns 404.

---

## 6. Target Group Health Checks

| Service | Health Check Path | Success Codes | Notes |
|---------|------------------|---------------|-------|
| Backend | `/health/` | `200` | Takes ~2.5 min to start (migrations + collectstatic) |
| Dashboard | `/dashboard/` | `200` | Fast startup |
| Storefront | `/` | `200,307` | Next.js redirects `/` → `/default-channel/` with 307 |

**Backend health check grace period: 300 seconds** (5 min)

The backend runs database migrations and collectstatic on every start, which takes ~2.5 minutes. If the grace period is too short (e.g., 120s), the ALB marks the task unhealthy before it's ready, ECS kills it, and it loops forever.

---

## 7. Secrets Manager

Create a secret named `saleor/<env>` with these keys:

```json
{
  "DATABASE_URL": "postgres://saleor:<URL_ENCODED_PASSWORD>@<RDS_ENDPOINT>:5432/saleor",
  "SECRET_KEY": "<random-long-string>",
  "ALLOWED_HOSTS": "<YOUR_DOMAIN>,localhost",
  "ALLOWED_CLIENT_HOSTS": "<YOUR_DOMAIN>,localhost",
  "EMAIL_URL": "smtp://localhost",
  "CELERY_BROKER_URL": "rediss://<REDIS_ENDPOINT>:6379/1",
  "CACHE_URL": "rediss://<REDIS_ENDPOINT>:6379/0"
}
```

### URL Encoding the Database Password

If the RDS password contains special characters (`#`, `?`, `>`, `(`, `)`, `$`, `|`, etc.), they MUST be URL-encoded in the DATABASE_URL. Otherwise the URL parser breaks.

```python
python3 -c "import urllib.parse; print(urllib.parse.quote('YOUR_PASSWORD_HERE', safe=''))"
```

Example: `iJ3>O)O5UNUYkT5M#.7s$|RB?s--` becomes `iJ3%3EO%29O5UNUYkT5M%23.7s%24%7CRB%3Fs--`

---

## 8. S3 Bucket for Media

- **ACLs enabled** → Bucket owner preferred (Saleor sets `public-read` ACL on uploads)
- **Block public access** → All 4 checkboxes UNCHECKED
- **Bucket policy** → Allow public `GetObject`:

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "PublicReadGetObject",
    "Effect": "Allow",
    "Principal": "*",
    "Action": "s3:GetObject",
    "Resource": "arn:aws:s3:::<BUCKET_NAME>/*"
  }]
}
```

---

## 9. Backend Environment Variables

### In task definition `environment` array:

| Variable | Value | Why |
|----------|-------|-----|
| `DEBUG` | `True` (dev) / `False` (prod) | Debug mode |
| `PUBLIC_URL` | `https://<YOUR_DOMAIN>` | Tells backend its external URL for generating thumbnail/media URLs. Without this, URLs default to `http://localhost:8000` |
| `AWS_MEDIA_BUCKET_NAME` | `<bucket-name>` | S3 bucket for media uploads |
| `AWS_STORAGE_BUCKET_NAME` | `<bucket-name>` | S3 bucket for static files |
| `AWS_S3_REGION_NAME` | `us-east-1` | S3 region |
| `AWS_MEDIA_CUSTOM_DOMAIN` | `<bucket-name>.s3.amazonaws.com` | Public URL for media files |
| `AWS_DEFAULT_ACL` | `public-read` | Make uploaded files publicly readable |
| `AWS_QUERYSTRING_AUTH` | `False` | Don't add auth tokens to S3 URLs |

### In task definition `secrets` array (from Secrets Manager):

DATABASE_URL, SECRET_KEY, ALLOWED_HOSTS, ALLOWED_CLIENT_HOSTS, EMAIL_URL, CELERY_BROKER_URL, CACHE_URL

---

## 10. Management Tasks (One-off ECS Tasks)

The `saleor-backend-manage` task definition is used for running Django management commands. It has:
- `entryPoint: ["sh", "-c"]` — overrides the default entrypoint so we can run any command
- Same env vars and secrets as the backend service
- **IMPORTANT: Must have S3 env vars** — otherwise `populatedb` saves images to the container's local filesystem which is destroyed when the task ends

### Run order after initial setup:

```bash
# 1. Populate sample data (products, orders, users, etc.)
aws ecs run-task --cluster <CLUSTER> --task-definition saleor-backend-manage \
  --launch-type FARGATE --network-configuration '...' \
  --overrides file://populate-data-override.json

# 2. Create admin user
aws ecs run-task --cluster <CLUSTER> --task-definition saleor-backend-manage \
  --launch-type FARGATE --network-configuration '...' \
  --overrides file://create-admin-override.json

# 3. Set Site domain (so thumbnail URLs use your domain, not localhost)
aws ecs run-task --cluster <CLUSTER> --task-definition saleor-backend-manage \
  --launch-type FARGATE --network-configuration '...' \
  --overrides file://update-site-domain-override.json

# 4. Pre-generate thumbnails (avoids trailing slash 404 issue)
# Run this script after populatedb:
MEDIA_IDS=$(curl -s 'https://<YOUR_DOMAIN>/graphql/' \
  -H 'Content-Type: application/json' \
  -d '{"query":"{ products(first:100, channel:\"default-channel\") { edges { node { media { id } } } } }"}' \
  | python3 -c "
import sys, json
data = json.load(sys.stdin)
for edge in data['data']['products']['edges']:
    for media in edge['node']['media']:
        print(media['id'])")

for ID in $MEDIA_IDS; do
  for SIZE in 256 1024 4096; do
    curl -s -o /dev/null "https://<YOUR_DOMAIN>/thumbnail/$ID/$SIZE/"
  done
done
```

---

## 11. Gotchas & Mistakes We Made

### Gotcha 1: Redis Cluster Mode
**Problem:** ElastiCache Redis created with cluster mode enabled. Celery uses `SELECT` command to switch databases, which is blocked in cluster mode.
**Error:** `redis.exceptions.ResponseError: SELECT is not allowed in cluster mode`
**Fix:** Create Redis with **cluster mode DISABLED**. Use `/0` for cache and `/1` for Celery broker.

### Gotcha 2: ENABLE_SSL breaks health checks
**Problem:** Setting `ENABLE_SSL=True` causes Django to redirect HTTP→HTTPS. ALB health checks use HTTP internally, so they get redirected and fail.
**Fix:** Don't use `ENABLE_SSL`. Use `PUBLIC_URL=https://<domain>` instead — it sets the correct protocol for URL generation without forcing SSL redirects.

### Gotcha 3: Dashboard STATIC_URL
**Problem:** Dashboard built without `STATIC_URL=/dashboard/` serves JS/CSS at root paths (`/index-xxx.js`). ALB routes these to storefront (default rule) → 404.
**Fix:** Always build dashboard with `--build-arg APP_MOUNT_URI=/dashboard/ --build-arg STATIC_URL=/dashboard/`.

### Gotcha 4: Storefront health check returns 307
**Problem:** Next.js storefront redirects `/` → `/default-channel/` with HTTP 307. ALB expects 200 → marks target unhealthy.
**Fix:** Set target group health check success codes to `200,307`.

### Gotcha 5: Management task missing S3 env vars
**Problem:** `populatedb` ran without S3 env vars → product images saved to container's local filesystem → container destroyed → images lost → thumbnails return 404.
**Fix:** Management task definition MUST have the same S3 env vars as the backend service.

### Gotcha 6: Site domain defaults to localhost
**Problem:** Django's `Site` model defaults to `localhost`. Backend generates thumbnail URLs as `http://localhost:8000/thumbnail/...` which browsers can't reach.
**Fix:** Run management task to set `Site.domain = '<your-domain>'`. Also set `PUBLIC_URL` env var.

### Gotcha 7: SiteSettings must exist
**Problem:** `populatedb` crashes at `create_site_settings()` due to schema mismatch. This means `SiteSettings` record is never created. Dashboard queries fail with `site.settings.limit_quantity_per_checkout` error.
**Fix:** Run management task to create SiteSettings: `SiteSettings.objects.get_or_create(site=Site.objects.get_current())`

### Gotcha 8: ECS entrypoint vs command
**Problem:** Backend Docker image has an entrypoint script. ECS `run-task` command override only replaces CMD (arguments to entrypoint), not the entrypoint itself. So management commands like `populatedb` don't work with the regular task definition.
**Fix:** Create a separate `saleor-backend-manage` task definition with `entryPoint: ["sh", "-c"]` to override the entrypoint.

### Gotcha 9: Backend startup takes ~2.5 minutes
**Problem:** Backend runs migrations + collectstatic on every start (~2.5 min). Default health check grace period (60-120s) is too short → ECS kills the task before it's ready → infinite restart loop.
**Fix:** Set health check grace period to **300 seconds** (5 min).

### Gotcha 10: Thumbnail trailing slash
**Problem:** Dashboard requests `/thumbnail/.../1024` (no trailing slash). Django URL pattern requires trailing slash. Saleor has `APPEND_SLASH=False`. Result: 404.
**Fix:** Pre-generate thumbnails by hitting each URL with trailing slash. Once cached in S3, the API returns direct S3 URLs, bypassing the `/thumbnail/` endpoint entirely.

### Gotcha 11: URL encoding in DATABASE_URL
**Problem:** RDS auto-generated password contains special characters (`#`, `?`, `>`, `$`, `|`) that break URL parsing in DATABASE_URL.
**Fix:** URL-encode the password using `python3 -c "import urllib.parse; print(urllib.parse.quote('password', safe=''))"`.

---

## 12. Dev vs Prod Differences

| Setting | Dev | Prod |
|---------|-----|------|
| VPC CIDR | 10.0.0.0/16 | 10.1.0.0/16 |
| ALB type | Internal or open to your IP | Internet-facing |
| CloudFront | No | Yes (CDN + caching) |
| WAF | No | Yes (blocks attacks) |
| ECS CPU/Memory | 512/1024 | 1024/2048 |
| RDS instance | db.t3.micro | db.t3.small + Multi-AZ |
| DEBUG | True | False |
| Secrets path | saleor/dev | saleor/prod |
| S3 bucket | saleor-media-dev-* | saleor-media-prod-* |
| PUBLIC_URL | https://dev.domain.com | https://domain.com |

---

## 13. Useful Commands

```bash
# Check ECS service status
aws ecs describe-services --cluster <CLUSTER> --services <SERVICE> \
  --query 'services[0].deployments[*].[status,runningCount,taskDefinition]'

# Force new deployment (picks up new secrets/task def)
aws ecs update-service --cluster <CLUSTER> --service <SERVICE> \
  --task-definition <TASK_DEF> --force-new-deployment

# Check target group health
aws elbv2 describe-target-health --target-group-arn <TG_ARN>

# View recent logs
aws logs filter-log-events --log-group-name <LOG_GROUP> \
  --start-time $(($(date +%s) - 3600))000 --filter-pattern "ERROR"

# Run one-off management task
aws ecs run-task --cluster <CLUSTER> --task-definition saleor-backend-manage \
  --launch-type FARGATE --network-configuration '{"awsvpcConfiguration":{"subnets":["subnet-xxx"],"securityGroups":["sg-xxx"],"assignPublicIp":"DISABLED"}}' \
  --overrides file://override.json
```
