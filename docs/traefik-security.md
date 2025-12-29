# Traefik Security Configuration

## TLS/HTTPS Setup

Traefik is already listening on ports 80 (HTTP) and 443 (HTTPS).

### Option 1: Let's Encrypt (Recommended for production)

For automatic TLS certificates, you'll need to configure cert-manager or Traefik's ACME:

```bash
# Install cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.0/cert-manager.yaml
```

Then create a ClusterIssuer for Let's Encrypt (requires public domain).

### Option 2: Self-Signed Certificates (For home/internal use)

Create self-signed certificates for internal services:

```bash
# Generate self-signed certificate
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout tls.key -out tls.crt \
  -subj "/CN=*.home.local/O=HomeLab"

# Create TLS secret
kubectl create secret tls traefik-tls --key=tls.key --cert=tls.crt -n default
```

## Middleware Configuration

### 1. Rate Limiting

Prevent abuse by limiting requests per IP:

```yaml
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: rate-limit
  namespace: default
spec:
  rateLimit:
    average: 100
    burst: 50
    period: 1s
```

### 2. HTTPS Redirect

Force all HTTP traffic to HTTPS:

```yaml
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: https-redirect
  namespace: default
spec:
  redirectScheme:
    scheme: https
    permanent: true
```

### 3. Security Headers

Add security headers to responses:

```yaml
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: security-headers
  namespace: default
spec:
  headers:
    frameDeny: true
    browserXssFilter: true
    contentTypeNosniff: true
    forceSTSHeader: true
    stsIncludeSubdomains: true
    stsPreload: true
    stsSeconds: 31536000
    customResponseHeaders:
      X-Frame-Options: "SAMEORIGIN"
      X-XSS-Protection: "1; mode=block"
```

### 4. Basic Authentication (for admin interfaces)

```bash
# Generate password hash
htpasswd -nb admin yourpassword

# Create secret
kubectl create secret generic traefik-auth \
  --from-literal=users='admin:$apr1$...' \
  -n default
```

```yaml
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: basic-auth
  namespace: default
spec:
  basicAuth:
    secret: traefik-auth
```

## Example Ingress with Security

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: secure-app
  namespace: default
  annotations:
    traefik.ingress.kubernetes.io/router.middlewares: default-https-redirect@kubernetescrd,default-rate-limit@kubernetescrd,default-security-headers@kubernetescrd
spec:
  tls:
  - hosts:
    - app.home.local
    secretName: traefik-tls
  rules:
  - host: app.home.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: my-app
            port:
              number: 80
```

## Current Access

- HTTP: http://192.168.0.206 (from LAN only - firewall protected)
- HTTPS: https://192.168.0.206 (from LAN only - firewall protected)

## Next Steps

1. Decide on certificate strategy (Let's Encrypt vs self-signed)
2. Apply middleware configurations
3. Configure ingress rules for your applications
4. Consider adding OAuth/OIDC for authentication (e.g., with Authelia or Keycloak)
