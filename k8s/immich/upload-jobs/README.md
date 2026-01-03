# Immich Bulk Upload Jobs

These jobs run inside k3s-master and upload photos directly from NAS to Immich.

## Setup (One-time)

1. Create API keys in Immich UI for each user
2. Create the secret:

```bash
kubectl delete secret immich-api-keys -n immich
kubectl create secret generic immich-api-keys -n immich \
  --from-literal=kanokgan-api-key="key1" \
  --from-literal=jongdee-api-key="key2"
```

Or update existing secret:
```bash
kubectl patch secret immich-api-keys -n immich --type merge -p '{"data":{"kanokgan-api-key":"BASE64_ENCODED_KEY"}}'
```

## Usage

1. Copy a template file (e.g., `user-template.yaml`)
2. Edit the values:
   - Job name
   - API key reference (user name)
   - NAS path
   - Optional: album name
3. Apply the job:

```bash
kubectl apply -f k8s/immich/upload-jobs/kanokgan-photos.yaml
```

4. Monitor progress:

```bash
kubectl logs -f job/JOBNAME -n immich
```

5. Check completion:

```bash
kubectl get jobs -n immich
```

## Notes

- Jobs auto-delete 1 hour after completion (ttlSecondsAfterFinished)
- Duplicate detection is enabled (skip-hash)
- 8 concurrent uploads
- If job fails, it retries up to 3 times
