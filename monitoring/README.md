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

This is a modest single-node setup rather than the full kube-prometheus-stack chart. It scrapes Prometheus, Loki, kube-state-metrics, and node-exporter; control-plane-specific metrics and alert routing are not configured yet. Alloy has cluster-wide read access to pod metadata/log streams through a narrowly scoped ClusterRole. Keep monitoring access private and avoid writing secrets or receipt contents to application logs.

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
