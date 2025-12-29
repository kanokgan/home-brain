# RBAC Best Practices

## Service Account Strategy

Always specify a service account in your deployments instead of using the default:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  template:
    spec:
      serviceAccountName: app-minimal  # Or app-readonly if needed
      automountServiceAccountToken: false  # Unless the app needs K8s API access
```

## Available Service Accounts

### `app-minimal`
- **Permissions**: None
- **Use for**: Most applications that don't need K8s API access
- **Auto-mount token**: Disabled

### `app-readonly`
- **Permissions**: Read ConfigMaps and Secrets in default namespace
- **Use for**: Apps that need to read configuration
- **Auto-mount token**: Disabled (enable in deployment if needed)

### `default`
- **Permissions**: None (we disabled auto-mount)
- **Use for**: Nothing - create specific service accounts instead

## Creating Custom Service Accounts

For apps with specific needs:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: my-app-sa
  namespace: default
automountServiceAccountToken: false
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: my-app-role
  namespace: default
rules:
- apiGroups: [""]
  resources: ["configmaps"]
  resourceNames: ["my-app-config"]  # Restrict to specific resources
  verbs: ["get"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: my-app-binding
  namespace: default
subjects:
- kind: ServiceAccount
  name: my-app-sa
roleRef:
  kind: Role
  name: my-app-role
  apiGroup: rbac.authorization.k8s.io
```

## Principle of Least Privilege

1. Start with `app-minimal` (no permissions)
2. Only grant permissions when needed
3. Use `Role` (namespace-scoped) instead of `ClusterRole` when possible
4. Restrict to specific resource names when possible
5. Never use `cluster-admin` for application workloads
