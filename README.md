# Laravel 12 + Docker + Helm (Minikube)

This repo contains a base Laravel 12 app with:
- Dockerfiles for dev (Artisan) and prod-ish (Apache)
- Entrypoints that generate APP_KEY and force file-based sessions/cache
- A Helm chart to deploy onto Kubernetes (tested on Minikube)

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

## Chart values
- `image.repository`: container repo (default `phpapp`)
- `image.tag`: image tag (default `apache`)
- `service.type`: `ClusterIP` (default) or `NodePort`
- `ingress.enabled`: `false` by default; set `true` to enable

## Notes
- Sessions and cache use file drivers; no DB required to serve the welcome page.
- Apache image exposes port 80; Helm Service targets this port.
