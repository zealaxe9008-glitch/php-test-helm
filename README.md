# Laravel 12 + Docker + Helm (Minikube)

This repo ships a clean Laravel 12 app plus everything you need to run it locally or on a cluster.

- Two Docker options: dev (Artisan) and prod-ish (Apache)
- Smart entrypoints that generate `APP_KEY` and default to file-based sessions/cache
- A small Helm chart that just works on Minikube (and other clusters)

## Prerequisites
- Docker 24+
- kubectl 1.24+
- Minikube 1.30+ (for local Kubernetes)
- Helm 3.11+
- sudo rights to edit `/etc/hosts` (only for local ingress testing)

---

## How this is put together (quick tour)
- Prod image (`Dockerfile.apache`): based on `php:8.3-apache`, installs the PHP bits we need (`pdo_sqlite`, `mbstring`, `zip`), sets `public/` as the docroot, and installs Composer (no dev deps).
- Dev image (`Dockerfile`): runs `php artisan serve` and builds Vite assets. Great for local hacking; not for prod.
- Entrypoint (`docker/apache-entrypoint.sh`): if there’s no `.env`, it copies `.env.example`, generates an `APP_KEY`, sets `SESSION_DRIVER=file` and `CACHE_STORE=file`, clears caches, and starts Apache.
- Helm chart (`deploy/helm/laravel-app`): a Deployment + Service, with optional Ingress. The production branch adds 2 replicas and health probes by default.

Why file-based sessions/cache?
- So you can boot the app with zero extra infra. When you’re ready, switch to DB/Redis by setting env vars or mounting your own `.env`.

---

## Local image or registry image?
You can run your own image two ways.

- Local to Minikube (fastest path):
```bash
docker build -f Dockerfile.apache -t phpapp:apache .
minikube image load phpapp:apache
helm upgrade --install laravel ./deploy/helm/laravel-app -n laravel \
  --set image.repository=phpapp --set image.tag=apache
```

- Pushed to a registry (works on any cluster):
```bash
IMAGE=ghcr.io/you/phpapp:1.0.0
docker build -f Dockerfile.apache -t $IMAGE .
docker push $IMAGE

kubectl create namespace laravel || true
kubectl create secret docker-registry regcred -n laravel \
  --docker-server=ghcr.io \
  --docker-username=YOUR_USER \
  --docker-password=YOUR_TOKEN

helm upgrade --install laravel ./deploy/helm/laravel-app -n laravel \
  --set image.repository=ghcr.io/you/phpapp \
  --set image.tag=1.0.0 \
  --set image.pullPolicy=IfNotPresent \
  --set-string image.pullSecrets[0].name=regcred
```

---

## How env works here
- No `.env` in the image? The entrypoint creates one from `.env.example` and generates an `APP_KEY`.
- To keep things simple, sessions/cache default to file drivers.
- If you already manage config in a `.env`, mount it as a Secret at `/var/www/html/.env` and it will be used.

Create and mount a `.env` Secret (optional, if you need custom config):
```bash
kubectl -n laravel create secret generic app-env --from-file=.env
# Then add a volume + volumeMount in the Deployment to mount it at /var/www/html/.env
```

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

## Deploy to Minikube with Ingress
```bash
minikube start

docker build -f Dockerfile.apache -t phpapp:apache .
minikube image load phpapp:apache

minikube addons enable ingress

kubectl create namespace laravel || true
helm upgrade --install laravel ./deploy/helm/laravel-app -n laravel \
  --set image.repository=phpapp \
  --set image.tag=apache \
  --set ingress.enabled=true \
  --set ingress.className=nginx \
  --set ingress.hosts[0].host=laravel.local \
  --set ingress.hosts[0].paths[0].path=/ \
  --set ingress.hosts[0].paths[0].pathType=Prefix

echo "$(minikube ip) laravel.local" | sudo tee -a /etc/hosts
curl -I http://laravel.local
```

What that Helm line means:
- `upgrade --install`: install if new; update if it exists.
- `laravel`: release name (you’ll see it in resource names).
- `./deploy/helm/laravel-app`: path to the chart.
- `-n laravel`: Kubernetes namespace.
- `--set image.*`: which image/tag to run.
- `--set ingress.*`: create an Ingress for `laravel.local` using the NGINX controller.

---

## Where things live
- `deploy/helm/laravel-app/values.yaml`: image, replicas, resources, env, service, ingress, securityContext
- `deploy/helm/laravel-app/templates/deployment.yaml`: container, probes, and where you’d mount a Secret as `/var/www/html/.env`
- `docker/apache-entrypoint.sh`: `.env` setup, key generation, default drivers, cache clear, start Apache

---

## Change the Helm deployment (simple first)
You don’t need to touch templates for most changes—just tweak `values.yaml` or pass flags.

- Use your own image:
```bash
helm upgrade laravel ./deploy/helm/laravel-app -n laravel \
  --set image.repository=your/repo --set image.tag=your-tag
```
- Scale up:
```bash
helm upgrade laravel ./deploy/helm/laravel-app -n laravel --set replicaCount=3
```
- Add env vars (if you’re not mounting `.env`):
```bash
helm upgrade laravel ./deploy/helm/laravel-app -n laravel \
  --set env[0].name=DB_CONNECTION --set env[0].value=mysql \
  --set env[1].name=DB_HOST --set env[1].value=mysql.default.svc.cluster.local \
  --set env[2].name=DB_DATABASE --set env[2].value=app \
  --set env[3].name=DB_USERNAME --set env[3].value=user \
  --set env[4].name=DB_PASSWORD --set env[4].value=pass
```
- Set resources:
```bash
helm upgrade laravel ./deploy/helm/laravel-app -n laravel \
  --set resources.requests.cpu=200m --set resources.requests.memory=256Mi \
  --set resources.limits.cpu=500m --set resources.limits.memory=512Mi
```
- NodePort instead of Ingress:
```bash
helm upgrade laravel ./deploy/helm/laravel-app -n laravel --set service.type=NodePort
minikube service laravel-laravel-app -n laravel --url
```

Prefer editing files instead of flags?
- Edit `values.yaml` (image, env, replicas, resources, service, ingress), then:
```bash
helm upgrade laravel ./deploy/helm/laravel-app -n laravel -f deploy/helm/laravel-app/values.yaml
```
- Need to mount a real `.env`? Edit `templates/deployment.yaml` to add a `volume` pointing to a Secret and a `volumeMount` at `/var/www/html/.env`.

---

## Scale, roll out, and see logs
```bash
kubectl rollout status deploy/laravel-laravel-app -n laravel
kubectl logs -n laravel deploy/laravel-laravel-app -c app --tail=200 -f
```

If you hit a 500 locally, common fixes:
- Cached config → the entrypoint runs `php artisan optimize:clear` on boot.
- Accidentally set DB-backed sessions/cache → remove those envs or set drivers to `file`.
- Ingress still starting → `kubectl get pods -n ingress-nginx` and wait for Ready.

---

## Production notes
- Runs as `www-data` (UID/GID 33). Change IDs in `values.yaml` if your image needs different ones.
- No DB included. Add DB/Redis and set envs (or mount `.env`).
- Want persistence? Mount a PVC to `storage/` and `bootstrap/cache/` and drop the permissive chmods.
- The `production` branch sets 2 replicas and adds health probes out of the box.
