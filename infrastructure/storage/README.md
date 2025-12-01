# Storage Configuration

## Overview

HomeBrain uses Synology DS923+ as the central storage appliance via NFS.

## Architecture

```
Synology DS923+ (NFS Server)
    ↓
K3s NFS CSI Driver
    ↓
PersistentVolumes (Dynamic Provisioning)
    ↓
Application Pods
```

## Setup Tasks

- [ ] Configure NFS exports on Synology
- [ ] Install NFS CSI driver on K3s
- [ ] Create StorageClass
- [ ] Test PVC provisioning

## Planned Storage Classes

- `nfs-standard` - General purpose storage
- `nfs-media` - Large files (Jellyfin, Immich)
- `nfs-backup` - Backup volumes
