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

## Customize the Helm deployment
- Image:
  - Change repo/tag: `--set image.repository=your/repo --set image.tag=your-tag`
  - Or edit `deploy/helm/laravel-app/values.yaml` under `image:`
- Replicas: `--set replicaCount=3`
- Resources: edit `values.yaml` `resources.requests/limits`
- Env vars: add under `values.yaml` `env:` (e.g., DB config)
- Ingress: toggle with `--set ingress.enabled=true` and adjust hosts/class/annotations
- Service type: `--set service.type=NodePort` (then `minikube service ... --url`)
- Probes: update HTTP paths/timings in `templates/deployment.yaml`
- Security context: adjust `podSecurityContext`/`securityContext` in `values.yaml`

Apply changes:
```bash
helm upgrade laravel ./deploy/helm/laravel-app -n laravel \
  --set image.repository=your/repo --set image.tag=your-tag
# or edit values.yaml and run:
helm upgrade laravel ./deploy/helm/laravel-app -n laravel -f deploy/helm/laravel-app/values.yaml
```

## Chart values
- `image.repository`: container repo (default `phpapp`)
- `image.tag`: image tag (default `apache`)
- `service.type`: `ClusterIP` (default) or `NodePort`
- `ingress.enabled`: `false` by default; set `true` to enable

## Notes
- Sessions and cache use file drivers; no DB required to serve the welcome page.
- Apache image exposes port 80; Helm Service targets this port.
