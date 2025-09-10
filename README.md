# Laravel 12 + Docker + Helm (Minikube)

This repo contains a base Laravel 12 app with:
- Dockerfiles for dev (Artisan) and prod-ish (Apache)
- Entrypoints that generate APP_KEY and force file-based sessions/cache
- A Helm chart to deploy onto Kubernetes (tested on Minikube)

## Prerequisites
- Docker 24+
- kubectl 1.24+
- Minikube 1.30+ (for local k8s)
- Helm 3.11+
- sudo access to edit /etc/hosts (for ingress host mapping)

---

## Architecture overview
- Image (prod): `Dockerfile.apache` builds on `php:8.3-apache`, installs required PHP extensions (`pdo_sqlite`, `mbstring`, `zip`), sets Apache DocumentRoot to `public/`, and installs Composer deps (no dev) with optimized autoload.
- Image (dev): `Dockerfile` (multi-stage) can run the Laravel dev server (`php artisan serve`) and also builds Vite assets. Useful for local development only.
- Entrypoints:
  - `docker/apache-entrypoint.sh`: ensures `.env` exists, generates `APP_KEY` if missing, sets `SESSION_DRIVER=file` and `CACHE_STORE=file`, clears caches, and starts Apache. This avoids DB requirements for a basic boot.
- Helm chart (`deploy/helm/laravel-app`): Deploys a single container Pod with a Service and optional Ingress. Probes and rolling strategy are included (see production branch for hardened defaults like 2 replicas and probes).

Why file-based sessions/cache?
- The base app should boot without provisioning DB/cache infra. For real apps, switch to your preferred drivers via environment variables and add backing services (MySQL/Redis).

---

## Run with Docker (Apache)

```bash
docker build -f Dockerfile.apache -t phpapp:apache .
docker run -d --name phpapp-apache -p 8080:80 phpapp:apache
# open http://localhost:8080
```

## Run with Docker (Artisan dev server)

```bash
docker build -t phpapp:dev .
docker run -d --name phpapp-dev -p 8000:8000 phpapp:dev
# open http://localhost:8000
```

---

## Deploy to Minikube with Helm + Ingress

```bash
# Build locally and load into minikube
minikube start
docker build -f Dockerfile.apache -t phpapp:apache .
minikube image load phpapp:apache

# Enable ingress controller
minikube addons enable ingress

# Install chart
kubectl create namespace laravel || true
helm upgrade --install laravel ./deploy/helm/laravel-app -n laravel \
  --set image.repository=phpapp \
  --set image.tag=apache \
  --set ingress.enabled=true \
  --set ingress.className=nginx \
  --set ingress.hosts[0].host=laravel.local \
  --set ingress.hosts[0].paths[0].path=/ \
  --set ingress.hosts[0].paths[0].pathType=Prefix

# Map the hostname to the minikube IP (Linux/macOS)
echo "$(minikube ip) laravel.local" | sudo tee -a /etc/hosts

# Test
curl -I http://laravel.local  # expect HTTP/1.1 200 OK
```

---

## Chart layout (what’s where)
- `Chart.yaml`: chart metadata
- `values.yaml`: default image, replicas, resources, env, service/ingress
- `templates/_helpers.tpl`: name helpers used in other templates
- `templates/deployment.yaml`: Pod/Deployment spec (ports, env, probes)
- `templates/service.yaml`: ClusterIP Service
- `templates/ingress.yaml`: optional Ingress (guarded by `ingress.enabled`)

---

## Customize the Helm deployment
- Image:
  - Change repo/tag: `--set image.repository=your/repo --set image.tag=your-tag`
  - Or edit `deploy/helm/laravel-app/values.yaml` under `image:`
- Replicas: `--set replicaCount=3`
- Resources: edit `values.yaml` `resources.requests/limits`
- Env vars: add under `values.yaml` `env:` (e.g., DB/Redis mailer config)
- Ingress: toggle with `--set ingress.enabled=true` and adjust hosts/class/annotations
- Service type: `--set service.type=NodePort` (then `minikube service ... --url`)
- Probes (readiness/liveness): adjust HTTP path (`/`) and timings in `templates/deployment.yaml`
- Security context: adjust `podSecurityContext`/`securityContext` in `values.yaml`

Apply changes:
```bash
# quick overrides
helm upgrade laravel ./deploy/helm/laravel-app -n laravel \
  --set image.repository=your/repo --set image.tag=your-tag

# or edit values.yaml and apply
helm upgrade laravel ./deploy/helm/laravel-app -n laravel -f deploy/helm/laravel-app/values.yaml
```

Production branch defaults
- See the `production` branch for: `replicaCount: 2`, readiness/liveness probes, and `Dockerfile.apache` with Composer dev-deps disabled and `APP_DEBUG=false`.

---

## Scaling and rollouts
- Scale replicas:
```bash
helm upgrade laravel ./deploy/helm/laravel-app -n laravel --set replicaCount=3
```
- Watch rollout:
```bash
kubectl rollout status deploy/laravel-laravel-app -n laravel
```
- Zero-downtime updates use a RollingUpdate strategy (maxSurge=1, maxUnavailable=0 on production branch).

---

## Logs and troubleshooting
- Pod logs:
```bash
kubectl logs -n laravel deploy/laravel-laravel-app -c app --tail=200 -f
```
- 500 errors locally (common causes):
  - Cached config from previous runs → entrypoint runs `php artisan optimize:clear`.
  - DB-backed session/cache drivers set by env → this chart defaults to `file`.
  - Ingress not ready → `kubectl get pods -n ingress-nginx` and wait for Ready.
- Port-forward alternative if not using ingress:
```bash
kubectl port-forward -n laravel deploy/laravel-laravel-app 8081:80
```

---

## Security & persistence notes
- This quickstart runs as `www-data` (UID/GID 33) and sets writable perms for `storage/` and `bootstrap/cache/`.
- No database is provisioned. If you need DB/Redis, add those services and set env vars. For persistent app storage, mount a PVC to `storage/` and `bootstrap/cache/` and remove the permissive chmods.
- For production, prefer an external cache/session store (e.g., Redis) and turn on proper logs/metrics.

---

## Chart values
- `image.repository`: container repo (default `phpapp`)
- `image.tag`: image tag (default `apache`)
- `service.type`: `ClusterIP` (default) or `NodePort`
- `ingress.enabled`: `false` by default; set `true` to enable

## Notes
- Sessions and cache use file drivers; no DB required to serve the welcome page.
- Apache image exposes port 80; Helm Service targets this port.
