# Payment Gateway & Processor – DevOps Take‑Home

## Overview

This repository contains a **minimal production‑ready** setup for the two micro‑services described in the assignment:

| Service            | Image                              | Port |
|--------------------|------------------------------------|------|
| **payment‑gateway**| `rajatg/payment-gateway:1.0.0`    | 8080 |
| **payment‑processor**| `rajatg/payment-processor:1.0.0`| 8080 |

Both services expose `GET /healthz`, `GET /readyz`, `GET /metrics` and the **gateway** forwards `POST /pay` to the **processor** via the `PROCESSOR_URL` environment variable.  All traffic is traced with an `X‑Request‑ID` header.

The goal of this repo is to provide a **reproducible local Kubernetes deployment** that mimics a production environment while keeping the footprint small enough for a quick start.

---

## Repository layout

```
.
├── k8s/                     # Raw Kubernetes manifests (YAML)
│   ├── namespace.yaml       # Optional isolated namespace
│   ├── configmap.yaml       # Configuration (env vars) for both services
│   ├── deployment-gateway.yaml
│   ├── deployment-processor.yaml
│   ├── service-gateway.yaml
│   └── service-processor.yaml
├── helm/                    # Minimal Helm chart (optional, for production upgrades)
│   └── payment-gateway-processor/ ...
├── .gitignore               # Ignore local tooling artefacts
├── Makefile                 # Helper commands (kind/minikube, apply, test)
└── README.md                # This documentation
```

Only the `k8s/` manifests are required to get the services running; the Helm chart is provided as a **future‑proof** path for production upgrades.

---

## Why this approach?

| Concern | How it is addressed |
|---------|---------------------|
| **Isolation** | All resources are created in a dedicated namespace `payment-system`. This mirrors a multi‑tenant cluster and prevents name clashes.
| **Configuration as code** | Environment variables are stored in a `ConfigMap`. Secrets (e.g., `SERVICE_TOKEN`) are deliberately kept as plain text in the example but should be moved to a `Secret` for real deployments.
| **Observability** | Both services expose Prometheus metrics (`/metrics`). The manifests expose those ports so a metrics collector can scrape them. Health/readiness probes are defined to enable Kubernetes self‑healing.
| **Reliability** | Restart policies (`Always`) and explicit `livenessProbe`/`readinessProbe` ensure pods are restarted on failure. `maxSurge`/`maxUnavailable` are set for rolling updates.
| **Network policy** (optional) | A simple `NetworkPolicy` can be added later to restrict traffic to only the allowed intra‑service flow.
| **Portability** | The `Makefile` supports both **Kind** (Docker‑in‑Docker) and **Minikube** – the two most common local K8s runtimes. No cloud‑specific resources are required.
| **Scalability** | Deployments are defined with `replicas: 2` (configurable) to demonstrate horizontal scaling.
| **Security baseline** | `runAsNonRoot: true` and `readOnlyRootFilesystem: true` are set where possible. The container images are pulled as‑is; in production you would scan them with an image‑security scanner.
| **CI/CD readiness** | The Helm chart provides a single source of truth for all manifests, making it trivial to plug into a GitOps pipeline (ArgoCD, Flux, Cloud Build, GitHub Actions, …).

---

## Getting started (macOS / Linux)

### Prerequisites

* **Docker** (v20+)
* **kubectl** (v1.28+)
* Either **Kind** (`brew install kind`) **or** **Minikube** (`brew install minikube`)
* **Make** (available on most Unix‑like systems)

> The repository works on Windows as well, but the `Makefile` targets assume a POSIX‑compatible shell. You can run the same commands manually with PowerShell if needed.

### 1. Spin up a local cluster

```bash
# Kind (recommended for fast start)
make kind-create   # creates a Kind cluster named "payment‑dev"

# …or Minikube
# make minikube-start
```

### 2. Deploy the services

```bash
make k8s-apply   # creates namespace, configmap, deployments & services
```

### 3. Verify health

```bash
# Replace <svc> with gateway or processor
kubectl -n payment-system get pods -o wide
kubectl -n payment-system port-forward svc/payment-gateway 8080:8080 &
curl -s http://localhost:8080/healthz | jq
curl -s http://localhost:8080/readyz | jq   # readiness checks processor reachability
```

You should receive `{"status":"OK"}` for both health endpoints.  A quick end‑to‑end test:

```bash
curl -s -X POST http://localhost:8080/pay \
  -H 'Content-Type: application/json' \
  -d '{"amount":100.50,"currency":"INR","payer":"acc-1","payee":"acc-2","reference":"inv-42"}' | jq
```

The response matches the specification in the assignment.

### 4. Clean up

```bash
make k8s-delete   # removes all resources from the namespace
make kind-delete  # destroys the Kind cluster (if you used Kind)
# make minikube-stop   # for Minikube
```

---

## Production checklist (what you would hand over)

1. **Helm chart** – version‑controlled, templated manifests.
2. **CI/CD pipeline** – e.g., GitHub Actions that lint Helm, run `helm template --dry-run`, and deploy on merge to `main`.
3. **Secure secrets** – move `SERVICE_TOKEN` into a Kubernetes `Secret` (or external secret manager like Google Secret Manager, Vault).
4. **Image scanning** – integrate Trivy or similar to scan the images before rollout.
5. **Resource quotas & limits** – add `resources.requests/limits` to the pod specs.
6. **PodDisruptionBudget** – guarantee service availability during node maintenance.
7. **NetworkPolicy** – restrict inbound/outbound traffic to only required ports and services.
8. **Observability stack** – Prometheus + Grafana dashboards for the `/metrics` endpoints; OpenTelemetry for trace propagation of `X‑Request‑ID`.
9. **Logging** – side‑car Fluent Bit/Fluentd to ship structured logs to a central system (ELK, Cloud Logging).
10. **Ingress** – expose the gateway externally via a TLS‑terminating Ingress controller (NGINX, Ambassador, GKE Ingress, …).
11. **Auto‑scaling** – HorizontalPodAutoscaler based on CPU/queue length.
12. **Disaster recovery** – backup of configuration and any stateful components (none for these stateless services, but the pattern is documented).
13. **Documentation** – versioned READMEs, runbooks for incident response, and run‑books for scaling/updates.

---

## Files generated by this repository

| Path | Purpose |
|------|---------|
| `k8s/namespace.yaml` | Creates `payment-system` namespace |
| `k8s/configmap.yaml` | Holds all non‑secret env vars (including default values) |
| `k8s/deployment-gateway.yaml` | Deployment for `payment-gateway` with health probes, env, and replica config |
| `k8s/deployment-processor.yaml` | Deployment for `payment-processor` with same conventions |
| `k8s/service-gateway.yaml` | ClusterIP service exposing port 8080 for internal calls and NodePort for local testing |
| `k8s/service-processor.yaml` | Service for the processor (used by the gateway via `PROCESSOR_URL`) |
| `helm/payment-gateway-processor/` | Minimal Helm chart – ready for GitOps |
| `Makefile` | Helper targets for local K8s lifecycle |
| `.gitignore` | Ignores local kubeconfig, Kind binaries, and temporary files |

---

## Next steps (optional)

* **Add a Helm values file** to customise replica counts, image tags, and resource limits without editing manifests.
* **Introduce a ServiceMesh** (e.g., Istio) for richer observability, retries, and circuit‑breaking.
* **Enable mutual TLS** between the two services using cert‑manager‑issued certificates.
* **Run load tests** with `hey` or `k6` to validate timeout/retry behaviour.

---

### Contact

If you need any adjustments, further automation (GitHub Actions, ArgoCD), or production‑grade hardening, let me know and I can extend the repo accordingly.

## Using Minikube (instead of Kind)

If you prefer **Minikube** as your local Kubernetes cluster, the existing `Makefile` already provides the necessary targets. The workflow is identical – just swap the *kind* helper for the *minikube* one.

### 1️⃣ Start Minikube
```bash
make minikube-start   # creates a Minikube VM and starts the cluster
```
You can optionally specify a driver, e.g. `minikube start --driver=docker` if you have Docker installed.

### 2️⃣ Deploy the manifests
```bash
make k8s-apply
```
The `Makefile` does **not** differentiate between Kind or Minikube – it simply runs `kubectl apply` against the current context, which will now be Minikube.

### 3️⃣ Verify & test
```bash
kubectl -n payment-system get pods
# Forward the gateway service (NodePort works out‑of‑the‑box, but you can also port‑forward)
kubectl -n payment-system port-forward svc/payment-gateway 8080:8080
curl -s -X POST http://localhost:8080/pay \
  -H 'Content-Type: application/json' \
  -d '{"amount":100.50,"currency":"INR","payer":"acc-1","payee":"acc-2","reference":"inv-42"}' | jq
```
You should see the same JSON response as with Kind.

### 4️⃣ Clean‑up
```bash
make k8s-delete   # removes the deployments, services, etc.
make minikube-stop # stops the Minikube VM (cluster persists for next run)
```

> **Tip:** If you ever need to switch back to Kind, just run `make kind-delete && make kind-create` – the manifests are cluster‑agnostic.
