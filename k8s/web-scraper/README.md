# Web Scraper Service

A Kubernetes-based manual web scraping system using wget to download and serve entire websites offline with high-performance caching.

## Overview

This is a **manual scraping system** for archiving websites to your K3s cluster. It uses:
- **Kubernetes Jobs** with `wget` to recursively download websites
- **Nginx** to serve the scraped content with aggressive caching
- **Tailscale** for secure private network access
- **ArgoCD** for GitOps deployment

**What it does:**
1. You manually create a Kubernetes Job to scrape a website
2. wget downloads all pages, images, CSS, JS with converted links for offline browsing
3. Nginx serves the content with 30-day caching for static assets
4. Access via Tailscale at `{sitename}-scrape.dove-komodo.ts.net`

## Key Features

- **Recursive wget scraping**: Downloads entire website trees with `--convert-links`
- **Offline browsing**: All links converted to work without internet
- **Aggressive caching**: 30-day cache for images/CSS/JS, immutable headers
- **Persistent storage**: 50Gi PVC stores all scraped content
- **Private access**: Tailscale integration, no public exposure
- **GitOps ready**: Managed via ArgoCD

## Quick Start

### 1. Deploy via ArgoCD

**First, create Tailscale secret:**
```bash
# Generate auth key at https://login.tailscale.com/admin/settings/keys
kubectl create secret generic tailscale-auth \
  --from-literal=TS_AUTHKEY="tskey-auth-YOUR_KEY_HERE" \
  -n web-scraper
```

**Deploy with ArgoCD:**
```bash
kubectl apply -f infrastructure/argocd/apps/web-scraper.yaml

# Wait for deployment
kubectl get pods -n web-scraper -w
```

### 2. Scrape a Website

**Edit `manual-scrape-job.yaml` with your target:**
```yaml
DOMAIN="example.com"
URL="https://example.com/docs/"
INCLUDE_DIRS="/docs/"
```

**Create the scraping job:**
```bash
kubectl apply -f k8s/web-scraper/manual-scrape-job.yaml

# Monitor progress (can take 30-90 minutes for large sites)
kubectl logs -f job/scrape-example -n web-scraper

# Check when complete
kubectl get jobs -n web-scraper
```

**Important wget options explained:**
- `--convert-links`: Converts absolute URLs to relative (critical for offline)
- `--page-requisites`: Downloads CSS, images, JS needed for display
- `--adjust-extension`: Adds .html to extensionless files
- `--no-clobber`: Skips already downloaded files

### 3. Update Deployment to Serve Content

**Edit `deployment.yaml` to match your scraped site:**
```yaml
# Line 29: Update subPath to match scraped domain
subPath: scraped/example.com

# Line 52: Update Tailscale hostname
value: "example-scrape"
```

**Apply changes:**
```bash
kubectl apply -f k8s/web-scraper/deployment.yaml
kubectl rollout restart deployment/web-scraper -n web-scraper
```

### 4. Access Your Scraped Site

Once deployed, access via Tailscale at:
```
http://example-scrape.dove-komodo.ts.net
```

The site will be **blazingly fast** with 30-day browser caching!

## Development Workflow

### Frontend Changes

```bash
cd app/scraper/web

# Make changes to React components
# Hot reload at http://localhost:3000

# When ready, build for production
npm run build

# Test with Go server
cd ..
go run main.go
# AHow It Works

### The Scraping Process

1. **Job Creation**: `manual-scrape-job.yaml` creates a Kubernetes Job
2. **wget Downloads**: Recursively downloads site with link conversion
3. **Storage**: Content saved to PVC at `/data/scraped/{domain}/`
4. **Serving**: Nginx mounts the scraped directory and serves with caching

### Aggressive Caching Strategy

The `nginx-config.yaml` configures:
- **Images (jpg, png, gif, svg, webp)**: 30 days, immutable
- **CSS/JS**: 30 days, immutable  
- **HTML**: 1 day (for potential updates)
- **Default**: 7 days for other assets

This makes page loads **extremely fast** after first visit.

### Troubleshooting

**Problem: Links point to original site**
- Solution: Ensure `--convert-links` is in wget command
- Note: Links only convert AFTER download completes

**Problem: CSS/Images broken**
- Solution: Check that `--page-requisites` is enabled
- Verify nginx is serving from correct `scraped/{domain}` subdirectory

**Problem: Directory listing instead of page**
- Solution: Check nginx `try_files` order in config
- Should be: `$uri $uri/ $uri/index.html $uri/index.htm =404`

**Problem: Job taking too long**
- This is normal for large sites (60-90 minutes)
- Check logs: `kubectl logs -f job/scrape-example -n web-scraper`
- Verify no 429 rate limiting errors

## Multiple Sites

To scrape multiple sites:

1. Create separate jobs with unique names:
   - `scrape-site1`, `scrape-site2`, etc.
   
2. Each creates its own directory:
   - `/data/scraped/site1.com/`
   - `/data/scraped/site2.com/`

3. Create separate deployments:
   - Update `subPath: scraped/site1.com`
   - Update `TS_HOSTNAME: site1-scrape`
   - Name deployment `web-scraper-site1`

4. Access at unique subdomains:
   - `site1-scrape.dove-komodo.ts.net`
   - `site2-scrape.dove-komodo.ts.net`

## Future Enhancements

Potential additions:
                           ┌──────────────────┐
                           │  User Browser    │
                           │   (Tailscale)    │
                           └────────┬─────────┘
                                    │ HTTP
                                    ▼
                    ┌───────────────────────────────┐
                    │   web-scraper Deployment      │
                    │  ┌─────────┐   ┌───────────┐ │
                    │  │  Nginx  │   │ Tailscale │ │
                    │  │  :80    │◄──┤  Sidecar  │ │
                    │  └────┬────┘   └───────────┘ │
                    │       │ read                  │
                    └───────┼───────────────────────┘
                            │
                            ▼
              ┌─────────────────────────────┐
              │   PVC: scraper-data (50Gi)  │
              │   /data/scraped/            │
              │     ├── site1.com/          │
              │     ├── site2.com/          │
              │     └── site3.com/          │
              └──────────▲──────────────────┘
                         │ write
                         │
              ┌──────────┴──────────┐
              │  Scraping Job       │
              │  ┌──────────────┐   │
              │  │  wget        │   │
              │  │  (alpine)    │   │
              │  └──────────────┘   │
              └─────────────────────┘
```

## File Manifest Reference

- `namespace.yaml` - Creates web-scraper namespace
- `pvc.yaml` - 50Gi storage for scraped content
- `rbac.yaml` - ServiceAccount with Job/Secret permissions for Tailscale
- `deployment.yaml` - Nginx + Tailscale sidecar
- `service.yaml` - ClusterIP service (port 80)
- `nginx-config.yaml` - Caching configuration
- `manual-scrape-job.yaml` - Template for wget scraping jobs
- `network-policy.yaml` - Network isolation rules
- `tailscale-config.yaml` - Tailscale ConfigMap
- `tailscale-pvc.yaml` - Tailscale state storage
- `tailscale-secret.yaml` - Template for Tailscale auth key

See `MANUAL-SCRAPING.md` for detailed step-by-step instructions.