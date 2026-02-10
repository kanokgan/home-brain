# K3s Disaster Recovery - Quick Deployment

## Initial Setup (One-time)

### 1. Verify NAS Directory

```bash
ssh kanokgan@k3s-master.dove-komodo.ts.net
ls -la /mnt/HomeBrain/backups/k3s-snapshots/
```

### 2. Deploy Backup Script

```bash
# From your local machine
cd ~/Developer/personal/home-brain

# Copy script to k3s-master
scp scripts/k3s-disaster-backup.sh kanokgan@k3s-master.dove-komodo.ts.net:/tmp/

# SSH and install
ssh kanokgan@k3s-master.dove-komodo.ts.net
sudo mkdir -p /root/scripts
sudo mv /tmp/k3s-disaster-backup.sh /root/scripts/
sudo chmod +x /root/scripts/k3s-disaster-backup.sh
sudo chown root:root /root/scripts/k3s-disaster-backup.sh
```

### 3. Test Backup Manually

```bash
# Run first backup
sudo /root/scripts/k3s-disaster-backup.sh

# Verify backup created
ls -lh /mnt/HomeBrain/backups/k3s-snapshots/latest/
cat /mnt/HomeBrain/backups/k3s-snapshots/latest/INVENTORY.txt
cat /var/log/k3s-disaster-backup.log
```

### 4. Deploy Automated Backup

**System Crontab (Recommended)**

The backup script requires direct access to k3s commands and systemctl, so it runs via system crontab instead of a Kubernetes CronJob.

```bash
# On k3s-master, add to root's crontab
sudo crontab -e
```

Add this line:
```cron
0 3 * * * /root/scripts/k3s-disaster-backup.sh >> /var/log/k3s-disaster-backup.log 2>&1
```

Or add directly:
```bash
(sudo crontab -l 2>/dev/null; echo "0 3 * * * /root/scripts/k3s-disaster-backup.sh >> /var/log/k3s-disaster-backup.log 2>&1") | sudo crontab -

# Verify crontab
sudo crontab -l

# Verify cron service
sudo systemctl status cron
```

## Daily Monitoring

```bash
# Check latest backup directory (on k3s-master)
ls -lh /mnt/HomeBrain/backups/k3s-snapshots/ | tail -5

# Check backup log
tail -20 /var/log/k3s-disaster-backup.log
```

## In Case of Disaster

```bash
# Identify latest backup
ls -lh /mnt/HomeBrain/backups/k3s-snapshots/

# Read restore instructions
cat /mnt/HomeBrain/backups/k3s-snapshots/latest/RESTORE.md

# Follow detailed runbook
# See: docs/runbooks/11-disaster-recovery.md
```

## Troubleshooting

**Backup failed:**
```bash
# Check logs
tail -100 /var/log/k3s-disaster-backup.log

# Verify NAS mount
df -h | grep HomeBrain

# Check permissions
ls -ld /mnt/HomeBrain/backups/k3s-snapshots/
```

**CronJob not running:**
```bash
kubectl get cronjobs -n kube-system
kubectl describe cronjob k3s-disaster-backup -n kube-system
kubectl logs -n kube-system -l app=k3s-disaster-backup --tail=50
```
