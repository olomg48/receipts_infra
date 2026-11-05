# Receipt Tracker Kubernetes configuration

Kustomize configuration for the single k3s cluster, with isolated `dev` and `prod` namespaces.

## Layout

```text
base/                 API and frontend Deployments and Services
overlays/dev/          Local dev image tags and in-cluster PostgreSQL
overlays/prod/         GHCR images and external PostgreSQL
monitoring/            Plain Kustomize manifests for Prometheus, Grafana, Loki, and Alloy
```

The API currently only exposes liveness and PostgreSQL readiness endpoints. Receipt uploads, authentication, the processing worker, and product-review APIs are not implemented yet, so this configuration does not deploy those features.

No ingress is configured; the frontend and API are internal ClusterIP Services. Add an Ingress and HTTPS after choosing hostnames and an ingress/TLS setup.

## Dev environment

The dev overlay starts with:

- Frontend: `ghcr.io/olomg48/receipt-tracker-frontend:dev`
- API: `ghcr.io/olomg48/receipt-tracker-backend:dev`
- PostgreSQL: `ghcr.io/olomg48/receipt-tracker-postgres:17-alpine`
- PostgreSQL StatefulSet with a 5 Gi PVC

The manual publisher in the application repo updates the application image tags to the application commit SHA and mirrors PostgreSQL 17 Alpine to GHCR. PostgreSQL uses a fixed `17-alpine` tag.

The dev PostgreSQL data survives pod restarts while its PVC remains. This single-node local-path storage is not a backup or high-availability solution. Verify the default StorageClass exists with `kubectl get storageclass`.

Create `overlays/dev/.secrets/dev-db.env` locally (the `.secrets/` directory is ignored by Git) with:

```dotenv
POSTGRES_DB=receipts
POSTGRES_USER=receipt_app
POSTGRES_PASSWORD=replace-with-a-strong-password
DATABASE_URL=postgresql+psycopg://receipt_app:replace-with-a-strong-password@receipt-postgres:5432/receipts
```

URL-encode special characters in the password used in `DATABASE_URL`. Then create the Secret before syncing the overlay:

```powershell
kubectl create namespace receipt-dev --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic receipt-db-credentials `
  --namespace receipt-dev `
  --from-env-file overlays/dev/.secrets/dev-db.env `
  --dry-run=client -o yaml | kubectl apply -f -
```

Do not commit that file or pass real secret values on a command line in a shared environment.

Apply with:

```sh
kubectl apply -k overlays/dev
kubectl -n receipt-dev get pods,services,pvc
```

For a GitOps-first setup, install Argo CD once, then create an Argo CD Application pointing to this repository's `overlays/dev` path. Use `kubectl apply -k` only as a temporary smoke test; let Argo CD own ongoing changes. With no Ingress, access the UI temporarily with:

```sh
kubectl -n receipt-dev port-forward service/receipt-frontend 8080:80
```

Then open `http://localhost:8080`.

## Prod environment

The prod overlay does not include PostgreSQL. It expects a pre-created Secret named `receipt-db-credentials` in namespace `receipt-prod`, with a `DATABASE_URL` key containing the external PostgreSQL SQLAlchemy URL. Configure TLS in the URL/provider connection settings. Do not put credentials in this repository.

The manual publisher in the application repo updates both prod image tags to the application commit SHA. The frontend/backend images are published to GHCR under:

```text
ghcr.io/olomg48/receipt-tracker-backend
ghcr.io/olomg48/receipt-tracker-frontend
```

Make GHCR packages public to pull without credentials, or add an `imagePullSecrets` reference and a pre-created registry Secret in `receipt-prod`. Do not enable automatic deployment from a mutable `latest` tag.

Apply with:

```sh
kubectl apply -k overlays/prod
```

Do not sync prod until the workflow has published the images and the database Secret is configured. The PostgreSQL migration is not currently an Argo CD hook; add a one-shot migration Job after the API schema and migration flow are ready.

## Kustomize validation

Render without applying:

```sh
kubectl kustomize overlays/dev
kubectl kustomize overlays/prod
```

NetworkPolicies and ingress are intentionally not included yet. Add and verify them after confirming the k3s CNI behavior, required DNS/API/database paths, and host-level exposure requirements.

## Monitoring

The [`monitoring/`](./monitoring/) Kustomize root contains Prometheus, Grafana, Loki, Alloy, and exporters as ordinary Kubernetes resources. Point an Argo CD Application at the `monitoring/` path. Follow its README to create the Grafana admin Secret first. The stack uses internal services and local-path PVCs; it does not expose a public ingress.
