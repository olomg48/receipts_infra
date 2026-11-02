# Receipt Tracker Kubernetes configuration

Kustomize configuration for the single k3s cluster, with isolated `dev` and `prod` namespaces.

## Layout

```text
base/                 API and frontend Deployments and Services
overlays/dev/          Local dev image tags and in-cluster PostgreSQL
overlays/prod/         GHCR images and external PostgreSQL
```

The API currently only exposes liveness and PostgreSQL readiness endpoints. Receipt uploads, authentication, the processing worker, and product-review APIs are not implemented yet, so this configuration does not deploy those features.

No ingress is configured; the frontend and API are internal ClusterIP Services. Add an Ingress and HTTPS after choosing hostnames and an ingress/TLS setup.

## Dev environment

The dev overlay deploys:

- Frontend: `receipt-tracker-frontend:dev`
- API: `receipt-tracker-backend:dev`
- PostgreSQL StatefulSet with a 5 Gi PVC

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

The `:dev` images are local development tags and must be present in k3s containerd. Docker Desktop images do not automatically exist on the k3s server. Build for the server architecture, transfer an archive to the server, and import it, for example:

```powershell
docker build --platform linux/amd64 -t receipt-tracker-backend:dev -f ..\recipts\backend\Dockerfile ..\recipts\backend
docker build --platform linux/amd64 -t receipt-tracker-frontend:dev -f ..\recipts\frontend\Dockerfile ..\recipts\frontend
docker save receipt-tracker-backend:dev receipt-tracker-frontend:dev -o receipt-tracker-images.tar
```

Copy the archive to the k3s server, then run:

```sh
sudo k3s ctr images import receipt-tracker-images.tar
```

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

Before deploying, replace `release-tag-required` in `overlays/prod/kustomization.yaml` with the immutable image tag or digest published by CI. The current frontend/backend images must be pushed to GHCR under:

```text
ghcr.io/olomg48/receipt-tracker-backend
ghcr.io/olomg48/receipt-tracker-frontend
```

Make GHCR packages public to pull without credentials, or add an `imagePullSecrets` reference and a pre-created registry Secret in `receipt-prod`. Do not enable automatic deployment from a mutable `latest` tag.

Apply with:

```sh
kubectl apply -k overlays/prod
```

Do not sync prod until images exist, the tag is set, and the database Secret is configured. The PostgreSQL migration is not currently an Argo CD hook; add a one-shot migration Job after the API schema and migration flow are ready.

## Kustomize validation

Render without applying:

```sh
kubectl kustomize overlays/dev
kubectl kustomize overlays/prod
```

NetworkPolicies and ingress are intentionally not included yet. Add and verify them after confirming the k3s CNI behavior, required DNS/API/database paths, and host-level exposure requirements.
