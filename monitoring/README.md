# Monitoring

This directory is a plain Kustomize root containing Kubernetes resources directly. Point an Argo CD Application at this repository path (`monitoring`); it creates the namespace and monitoring workloads. There are no nested Argo CD `Application` objects or Helm chart dependencies.

The starter stack contains:

- Prometheus, with seven-day retention and an 8 Gi persistent volume.
- Grafana, with Prometheus and Loki data sources provisioned and a 2 Gi persistent volume.
- Loki in single-process filesystem mode, with seven-day log retention and a 10 Gi persistent volume.
- Alloy, which reads pod logs through the Kubernetes API and forwards them to Loki.
- kube-state-metrics and node-exporter, which provide cluster object and host metrics to Prometheus.

## Secret prerequisite

Create the Grafana admin Secret in the `monitoring` namespace before Argo CD syncs the stack:

```powershell
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic grafana-admin-credentials `
  --namespace monitoring `
  --from-literal=admin-user=admin `
  --from-literal=admin-password='replace-with-a-strong-password'
```

Do not commit the password or embed it in manifests. Use your later secrets-management mechanism when ready.

## Storage and resource planning

The three PVCs request 20 Gi total, in addition to the application database storage. They assume the k3s `local-path` StorageClass; check with `kubectl get storageclass` and ensure there is enough disk before syncing. Local-path volumes are single-node storage, not backups or high availability. Log/metric retention is intentionally short to bound disk use.

Each service has its own container memory request and limit:

| Service | Request | Limit |
| --- | ---: | ---: |
| Prometheus | 512 Mi | 1536 Mi |
| Loki | 384 Mi | 1536 Mi |
| Grafana | 192 Mi | 512 Mi |
| Alloy | 96 Mi | 256 Mi |
| kube-state-metrics | 48 Mi | 128 Mi |
| node-exporter (per node) | 32 Mi | 128 Mi |

On a single-node cluster, these add up to about 1.24 Gi of requests and 4 Gi of limits. The namespace `ResourceQuota` is a separate aggregate backstop: 8 Gi for total memory requests and 10 Gi for total memory limits. The `LimitRange` defaults any new container without explicit memory resources to a 512 Mi limit and 128 Mi request, and rejects a container limit above 1536 Mi. These policies apply only in the `monitoring` namespace; they do not reserve 10 Gi for monitoring or limit other namespaces. Leave enough RAM for the OS, k3s, and application workloads.

This is a modest single-node setup rather than the full kube-prometheus-stack chart. It scrapes Prometheus, Loki, kube-state-metrics, and node-exporter; control-plane-specific metrics and alert routing are not configured yet. Alloy has cluster-wide read access to pod metadata/log streams through a narrowly scoped ClusterRole. Keep monitoring access private and avoid writing secrets or receipt contents to application logs.

For node-exporter, Prometheus discovers pods in the `monitoring` namespace and sets the `instance` label to the Kubernetes node name hosting each exporter pod. Its service account has only namespaced pod get/list/watch permissions for discovery. Other scrape jobs keep their normal target-based `instance` labels.

Images are pinned to explicit upstream versions. They are pulled from the upstream registries referenced in the manifests; this monitoring stack does not yet mirror third-party images into GHCR.

## Access and validation

Services are ClusterIP only. To access Grafana without an Ingress:

```powershell
kubectl -n monitoring port-forward service/grafana 3000:3000
```

Open `http://localhost:3000` and use the credentials from `grafana-admin-credentials`.

Render the resources without applying them:

```powershell
kubectl kustomize monitoring
```
