# Receipt Tracker Infrastructure

Infrastructure-as-code for a personal receipt-tracking application running on a Proxmox-backed k3s cluster. The repository demonstrates VM provisioning with Terraform, cluster bootstrap with Ansible, Kubernetes deployments with Kustomize, GitOps reconciliation with Argo CD, and a self-hosted monitoring stack.

The application source is in [olomg48/receipts](https://github.com/olomg48/receipts). Its [architecture summary](https://github.com/olomg48/receipts/blob/main/ARCHITECTURE-SUMMARY.md) describes the application design and processing workflow.

> **AI authorship disclosure:** The application is almost entirely AI-generated. This portfolio project focuses on infrastructure and DevOps; the application provides the system being deployed. This README was AI-generated.

> **Project status:** This is a homelab/CV project, not a hardened public service. The app has no user authentication, current ingresses use HTTP, Prometheus is unauthenticated, and the Garage deployment does not yet have persistent storage. See [Current limitations](#current-limitations) before using it with data you need to keep or exposing it beyond a trusted network.

## Architecture

```text
Proxmox host
  └─ Terraform provisions three VMs (one master, two workers)
       └─ Ansible installs and joins k3s
            ├─ Argo CD (installed separately; this repo supplies an ingress)
            ├─ receipt-dev namespace
            │    ├─ Frontend, API, worker, Garage, migrations
            │    └─ PostgreSQL 18 for development
            ├─ receipt-prod namespace
            │    ├─ Frontend, API, worker, Garage, migrations
            │    └─ External PostgreSQL SaaS
            └─ monitoring namespace
                 ├─ Prometheus, Grafana, Loki, Alloy
                 └─ kube-state-metrics, node-exporter

Browser
  └─ Traefik Ingress (currently HTTP)
       └─ React frontend / Nginx
            └─ /api proxy ──> FastAPI API ──> PostgreSQL
                                    └───────> Garage (S3-compatible)

PostgreSQL receipt job queue ──> Python worker
                                  ├─ reads/writes receipt artifacts in Garage
                                  └─ Mistral OCR, then Mistral LLM extraction
```

Terraform currently describes three VMs, each configured with 2 vCPUs and 4 GiB of RAM. The application architecture document records a 16 GiB, 4-core host, so those VM definitions allocate 6 vCPUs and 12 GiB before Proxmox and host overhead. Treat these as VM settings, not a guarantee of physical capacity, and watch for CPU overcommit and memory pressure when running the full stack.

### Application components

- **Frontend:** React and TypeScript, served by Nginx. Nginx serves the single-page app and proxies `/api/` requests to the API service.
- **API:** FastAPI handles receipt uploads and history/details, product-code review, analytics, health checks, and failed-job reprocessing.
- **Worker:** A separate process from the same backend image. It claims durable jobs from PostgreSQL, runs OCR and structured extraction through Mistral, validates results, and stores artifacts in Garage.
- **PostgreSQL:** Development uses an in-cluster PostgreSQL StatefulSet. The production overlay expects an external PostgreSQL service and does not deploy a database.
- **Garage:** S3-compatible storage for private receipt files and processing artifacts. The current base deploys a single Garage pod.
- **BI:** The app has an Insights view. Metabase is not deployed by this repository; it remains a possible later addition.

There is no application login or per-user data separation. Any client that can reach the app can view and modify its receipt data. Keep access restricted to trusted devices/networks.

## Repository layout

```text
terraform/                  Proxmox provider config and reusable VM module
ansible/                    k3s master/worker inventory and bootstrap playbook
base/                       Shared app Deployments, Services, Garage, RBAC, migration Job
overlays/dev/               Dev namespace, in-cluster PostgreSQL, dev ingress and image tags
overlays/prod/              Prod namespace and production image tags
monitoring/                 Monitoring workloads, ingress, configuration and resource policies
```

Kustomize is used to compose a shared application base with environment overlays. The monitoring stack is a separate Kustomize root. The `base/` directory is included through an overlay and is not intended to be deployed on its own.

## Terraform and Ansible

Terraform uses the `bpg/proxmox` provider and a reusable `terraform/modules/proxmox_vm` module. The current configuration clones three VMs from a Proxmox template and outputs their IP addresses. Supply the Proxmox API token through a local, ignored variable file or the `TF_VAR_token` environment variable; never commit credentials or state.

Ansible bootstraps k3s on the master, reads the k3s node token there, and joins the two workers. The inventory and provider currently contain environment-specific settings. Review those values and the security notes below before publishing or reusing this configuration.

Example checks:

```powershell
terraform -chdir=terraform init
terraform -chdir=terraform validate
ansible-playbook -i ansible/hosts ansible/main.yaml --syntax-check
```

Provisioning VMs or installing k3s is intentionally not part of the application deployment workflow.

## Kustomize environments

### Development

`overlays/dev` composes `base/` with:

- Namespace `receipt-dev`.
- PostgreSQL 18 as a single-replica StatefulSet with a 5 Gi `local-path` PVC.
- A Traefik Ingress for `receipts.dev.local`, routed to the frontend.
- GHCR image references pinned to an application commit.

The API and worker use the PostgreSQL Secret and Garage credentials in the same namespace. The dev database PVC survives pod restarts while the claim and node remain available; it is not a backup or HA solution.

### Production

`overlays/prod` composes `base/` in namespace `receipt-prod` and expects an external PostgreSQL connection. It does not currently define a production Ingress or TLS configuration. Its image tags are placeholders until a release workflow updates them.

Do not treat the current prod overlay as internet-ready. Configure its public origin, ingress/TLS, network access, and required runtime Secrets before deploying it.

### Render manifests

Render each root without applying it:

```powershell
kubectl kustomize overlays/dev
kubectl kustomize overlays/prod
kubectl kustomize monitoring
```

The app Deployment manifests reference a `ghcr-secret` image pull Secret. Create it in each app namespace when required by package visibility, or adjust the manifests for anonymous pulls from public GHCR packages.

## Argo CD and deployment flow

Argo CD is expected to manage ongoing changes, but its installation and Argo CD `Application` resources are **not** defined in this repository. Install Argo CD separately, then create Applications that point to:

| Argo CD Application | Repository path | Namespace |
| --- | --- | --- |
| Receipt development | `overlays/dev` | `receipt-dev` |
| Receipt production | `overlays/prod` | `receipt-prod` |
| Monitoring | `monitoring` | `monitoring` |

`monitoring/argo-ingress.yaml` provides an HTTP Traefik route for `argo.local` to an already-installed `argocd-server` Service. It does not install or configure Argo CD itself.

The database migration Job in `base/db-job.yaml` is an Argo CD `PreSync` hook. It runs Alembic migrations with the application image before the updated application resources are applied.

The application repository has a manually dispatched GitHub Actions workflow. It tests the backend, builds and publishes the frontend/backend images to GHCR using the application commit SHA, then commits the selected environment's image-tag update to this repository. The workflow needs an `INFRA_REPO_TOKEN` secret with permission to push to the infrastructure repository. Argo CD reconciles the changed overlay according to its Application sync policy.

Use `kubectl apply -k` only for a deliberate local smoke test; avoid using it as a second controller for resources Argo CD owns.

## Secrets and configuration

No runtime credential values should be committed to this repository. The Kubernetes Secrets below must be created out of band in the namespace where the corresponding workloads run:

| Secret | Namespace | Required data / purpose |
| --- | --- | --- |
| `receipt-db-credentials` | `receipt-dev` | `POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD`, and `DATABASE_URL` for the dev PostgreSQL instance |
| `receipt-db-credentials` | `receipt-prod` | `DATABASE_URL` for the external PostgreSQL service; use the provider's TLS settings |
| `garage-secrets` | Each app namespace | `GARAGE_RPC_SECRET` and `GARAGE_ADMIN_TOKEN` for Garage |
| `garage-s3-credentials` | Each app namespace | Generated by the Garage initialization Job; app-specific S3 access key and secret |
| `receipt-mistral-credentials` | Each app namespace | `MISTRAL_API_KEY` for the worker |
| `ghcr-secret` | Each app namespace | Image pull credentials when GHCR packages are private |
| `grafana-admin-credentials` | `monitoring` | `admin-user` and `admin-password` for Grafana |

The Garage initialization Job uses the admin token to create or reuse the private receipt bucket and an app key, grants that key access to the bucket, then writes the generated S3 credentials to `garage-s3-credentials`. Its service account is limited to managing Secrets in its namespace.

For a personal cluster, provision Secrets with a secure local process before syncing the relevant Argo CD Application. Kubernetes Secret manifests are not encrypted merely because their values are base64 encoded. This repository does not currently configure SOPS, Sealed Secrets, External Secrets, or another encrypted GitOps secret workflow. Do not put secret values in Git, CI logs, command history, or this README.

`PUBLIC_APP_ORIGIN` is a non-secret browser-origin setting, not authentication. It must match the browser-facing origin. The current base value is for the dev hostname; override it for any other environment.

## Monitoring stack

The `monitoring/` Kustomize root deploys a lightweight, single-cluster observability stack:

- **Prometheus:** scrapes Prometheus, Loki, kube-state-metrics, and node-exporter; 7-day retention and an 8 Gi PVC.
- **Grafana:** provisioned Prometheus and Loki data sources; 2 Gi PVC; admin credentials come from a Secret.
- **Loki:** single-process filesystem storage with 7-day retention and a 10 Gi PVC.
- **Alloy:** discovers Kubernetes pods and forwards pod logs to Loki.
- **kube-state-metrics:** exposes Kubernetes object metrics.
- **node-exporter:** runs on cluster nodes to expose host metrics.
- **ResourceQuota/LimitRange:** bound memory requests and limits in the monitoring namespace.

The monitoring Ingress routes `grafana.local` and `prometheus.local`; the Argo CD Ingress routes `argo.local`. These manifests use HTTP and do not configure TLS. Prometheus has no authentication configured, so restrict these routes to a trusted network. Loki is internal to the cluster.

Alloy is configured to collect pod logs cluster-wide. Avoid emitting receipt contents, OCR text, credentials, or other sensitive values to application logs. If application log collection is not wanted, update Alloy's discovery/collection configuration before deployment.

The monitoring PVCs request 20 Gi total and use the k3s `local-path` StorageClass. They are node-local storage, not backups or high-availability storage. The monitoring README contains resource details and host-resolution instructions.

## Current limitations and public-repository checklist

- **Authentication:** The receipt app has no login or user isolation. Do not expose it to the public internet in its current form.
- **Transport security:** App, monitoring, and Argo CD Ingress manifests currently use HTTP; TLS is not configured.
- **Prometheus access:** The Prometheus UI has no authentication.
- **Receipt durability:** Garage is a single-replica Deployment and currently has no PVC mounted for its configured data directories. Receipt objects can be lost when the pod is replaced. Add persistent storage and test backups before relying on it.
- **Database/monitoring durability:** Dev PostgreSQL and monitoring data use local-path storage. No off-host backup or restore automation is defined here.
- **Network policy:** No Kubernetes NetworkPolicies are included.
- **Infrastructure identity checks:** The current Proxmox provider configuration disables TLS certificate verification, and the Ansible inventory disables SSH host-key checking. Correct these before treating the setup as hardened.
- **Environment-specific data:** `ansible/hosts` and `terraform/main.tf` contain private-network/Proxmox details and a local key-file path. Replace or parameterize these for a public portfolio repository. The Terraform module also contains an SSH public key; verify it is an intentionally public deployment key.
- **Secrets:** Terraform state, local variable files, and Kubernetes Secret values must remain outside public Git. Confirm repository history and all staged/untracked files are clean before making the repository public.

## Related documentation

- [Monitoring stack details](monitoring/README.md)
- [Application repository](https://github.com/olomg48/receipts)
- [Application architecture](https://github.com/olomg48/receipts/blob/main/ARCHITECTURE-SUMMARY.md)
