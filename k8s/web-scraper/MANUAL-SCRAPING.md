# Manual Scraping Quick Start

Quick guide to manually scrape websites and serve them through Tailscale.

## 1. Edit the Job for Your Target

Edit `k8s/web-scraper/manual-scrape-job.yaml`:

```yaml
# Change these variables:
DOMAIN="yoursite.com"                    # Domain name
URL="https://yoursite.com/path/"         # Starting URL
INCLUDE_DIRS="/path/"                    # Directories to include
```

## 2. Run the Scraping Job

```bash
# Apply the job
kubectl apply -f k8s/web-scraper/manual-scrape-job.yaml

# Watch progress
kubectl logs -f -n web-scraper job/scrape-example

# Check status
kubectl get jobs -n web-scraper
```

## 3. Access Scraped Content

Once complete, access via Tailscale:

```
http://scrap.dove-komodo.ts.net/yoursite.com/
```

The Go server will automatically serve content from `/data/scraped/{domain}/`

## 4. Clean Up

```bash
# Delete completed job
kubectl delete job scrape-example -n web-scraper

# To re-run, change job name or delete first
```

## Example: Scrape Multiple Sites

Create separate job files or run sequentially:

```bash
# Copy template
cp k8s/web-scraper/manual-scrape-job.yaml scrape-site1.yaml

# Edit variables
vim scrape-site1.yaml

# Run
kubectl apply -f scrape-site1.yaml
```

## Directory Structure

Scraped content is stored as:
```
/data/scraped/
├── example.com/
│   └── docs/
│       └── index.html
├── another-site.com/
│   └── page.html
```

Access as:
- `http://scrap.dove-komodo.ts.net/example.com/docs/`
- `http://scrap.dove-komodo.ts.net/another-site.com/page.html`

## Troubleshooting

**Job fails:**
```bash
kubectl describe job scrape-example -n web-scraper
kubectl logs -n web-scraper -l job-name=scrape-example
```

**Content not showing:**
```bash
# Check PVC
kubectl exec -it -n web-scraper deployment/web-scraper -c scraper -- ls -la /data/scraped/

# Check if domain directory exists
kubectl exec -it -n web-scraper deployment/web-scraper -c scraper -- ls -la /data/scraped/yoursite.com/
```

**Rescrape (update content):**
```bash
# Delete job
kubectl delete job scrape-example -n web-scraper

# Edit if needed
vim k8s/web-scraper/manual-scrape-job.yaml

# Run again
kubectl apply -f k8s/web-scraper/manual-scrape-job.yaml
```

## Advanced: Custom wget Options

Edit the job to add more wget options:

```yaml
wget -r -l 2 \                          # Limit depth to 2
  --no-parent \
  --domains=$DOMAIN \
  --include-directories=$INCLUDE_DIRS \
  --reject="*.pdf,*.zip" \              # Reject certain files
  --wait=1 \                            # Wait between requests
  --page-requisites \
  --convert-links \
  --adjust-extension \
  --no-clobber \
  $URL
```

## Notes

- Scraping respects `--no-clobber` (won't overwrite existing files)
- Each domain gets its own directory
- Go server automatically detects and serves from `/data/scraped/{domain}/`
- Content persists in PVC across pod restarts
- Only accessible via Tailscale network
