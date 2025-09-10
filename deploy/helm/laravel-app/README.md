# laravel-app Helm Chart

Simple chart to deploy the Laravel 12 Apache image.

## Install

```
helm upgrade --install laravel \
  ./deploy/helm/laravel-app \
  --set image.repository=phpapp \
  --set image.tag=apache
```

## Enable ingress

```
helm upgrade --install laravel \
  ./deploy/helm/laravel-app \
  --set ingress.enabled=true \
  --set ingress.hosts[0].host=laravel.local \
  --set ingress.hosts[0].paths[0].path=/ \
  --set ingress.hosts[0].paths[0].pathType=Prefix
```
