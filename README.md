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

## Images: local vs registry
You have two ways to make the image available to your cluster.

- Local image (Minikube): build locally and import into Minikube’s runtime
```bash
docker build -f Dockerfile.apache -t phpapp:apache .
minikube image load phpapp:apache
helm upgrade --install laravel ./deploy/helm/laravel-app -n laravel \
  --set image.repository=phpapp --set image.tag=apache
```

- Registry image (any Kubernetes): push to a registry and reference it
```bash
# example: ghcr.io/you/phpapp:1.0.0 or your ECR/GCR/ACR
IMAGE=ghcr.io/you/phpapp:1.0.0
docker build -f Dockerfile.apache -t $IMAGE .
docker push $IMAGE

# create a pull secret (one time per namespace)
kubectl create secret docker-registry regcred -n laravel \
  --docker-server=ghcr.io \
  --docker-username=YOUR_USER \
  --docker-password=YOUR_TOKEN

# tell Helm to use your image + pull secret
helm upgrade --install laravel ./deploy/helm/laravel-app -n laravel \
  --set image.repository=ghcr.io/you/phpapp \
  --set image.tag=1.0.0 \
  --set image.pullPolicy=IfNotPresent \
  --set-string image.pullSecrets[0].name=regcred
```
If your chart doesn’t yet support `image.pullSecrets`, add it under `spec.template.spec.imagePullSecrets` in the Deployment template, or store that in `values.yaml` and template it.

---

## How env is handled (matches this project)
- Default behavior inside the container:
  - If no `.env` is present, the entrypoint copies `.env.example` to `.env` and generates an `APP_KEY`.
  - It forces `SESSION_DRIVER=file` and `CACHE_STORE=file` so the app runs without DB/Redis.
- Recommended ways to provide configuration beyond defaults:
  1) Plain env vars via Helm `values.yaml` (simple for small sets)
     - Add items under `values.yaml` → `env:` and re-`helm upgrade`.
  2) Provide a `.env` file via Secret and mount it (best when you already use `.env`)
     - Create a Secret from your `.env`:
```bash
kubectl -n laravel create secret generic app-env --from-file=.env
```
     - Mount it to `/var/www/html/.env` in the Deployment (add a `volumes` entry and a `volumeMounts` entry). The entrypoint will detect the file and skip generating.
  3) Provide sensitive items via Secrets and reference them as env vars (e.g., `DB_PASSWORD`)

Note: If both a mounted `.env` and env vars are present, Laravel will read from `.env`. Keep a single source of truth to avoid confusion.

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

## Customize the Helm deployment (beginner-friendly)
You usually don’t edit the templates. Instead, you pass values at install/upgrade time, or edit `values.yaml` and re-run `helm upgrade`.

Think of `values.yaml` as the “settings” file. Here are the most common things you’ll change, with exact commands.

1) Change the container image
- Local/minikube image:
```bash
helm upgrade --install laravel ./deploy/helm/laravel-app -n laravel \
  --set image.repository=phpapp --set image.tag=apache
```
- Registry image (with a pull secret): see “Images: local vs registry”.

2) Scale the app up/down
```bash
helm upgrade laravel ./deploy/helm/laravel-app -n laravel \
  --set replicaCount=3
```

3) Add environment variables (e.g., point to a DB)
```bash
helm upgrade laravel ./deploy/helm/laravel-app -n laravel \
  --set env[0].name=DB_CONNECTION --set env[0].value=mysql \
  --set env[1].name=DB_HOST --set env[1].value=mysql.default.svc.cluster.local \
  --set env[2].name=DB_DATABASE --set env[2].value=app \
  --set env[3].name=DB_USERNAME --set env[3].value=user \
  --set env[4].name=DB_PASSWORD --set env[4].value=pass
```
Tip: If you already manage config in a `.env`, mount it via Secret as described above.

4) Adjust CPU/Memory resources
```bash
# Example: request 200m CPU/256Mi and limit 500m/512Mi
helm upgrade laravel ./deploy/helm/laravel-app -n laravel \
  --set resources.requests.cpu=200m \
  --set resources.requests.memory=256Mi \
  --set resources.limits.cpu=500m \
  --set resources.limits.memory=512Mi
```

5) Switch Service type (NodePort for external access without Ingress)
```bash
helm upgrade laravel ./deploy/helm/laravel-app -n laravel \
  --set service.type=NodePort
minikube service laravel-laravel-app -n laravel --url
```

6) Enable/modify Ingress
```bash
helm upgrade laravel ./deploy/helm/laravel-app -n laravel \
  --set ingress.enabled=true \
  --set ingress.className=nginx \
  --set ingress.hosts[0].host=myapp.local \
  --set ingress.hosts[0].paths[0].path=/ \
  --set ingress.hosts[0].paths[0].pathType=Prefix
# add "$(minikube ip) myapp.local" to /etc/hosts for local testing
```

7) Tweak health checks (readiness/liveness probes)
- The chart defaults to probing `/` on port 80. If your health URL is different (e.g., `/health`), edit `templates/deployment.yaml` or fork the chart. For simple apps, `/` works.

8) Security context (run as non-root)
- By default, the container runs as `www-data` (UID/GID 33). If your base image needs other IDs, edit these in `values.yaml` under `podSecurityContext` and `securityContext`.

If you ever get stuck, see what values are currently in use:
```bash
helm get values laravel -n laravel -a
```

### Prefer editing files instead of CLI flags?
- Edit `deploy/helm/laravel-app/values.yaml`:
  - `image.repository`, `image.tag`, `image.pullPolicy`
  - `replicaCount`
  - `env:` (list of name/value pairs)
  - `resources.requests/limits`
  - `service.type`, `service.port`
  - `ingress.*` (enabled, className, hosts, annotations)
- Then apply:
```bash
helm upgrade laravel ./deploy/helm/laravel-app -n laravel -f deploy/helm/laravel-app/values.yaml
```
- If you truly need to change structure (e.g., mount a Secret as `.env`, add volumes), edit `templates/deployment.yaml`:
  - Add a `volumes:` entry pointing to your Secret/ConfigMap
  - Add `volumeMounts:` to mount it at `/var/www/html/.env`
  - Reason: this binds your `.env` into the container so the entrypoint detects and uses it.

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
