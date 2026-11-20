# Makefile for local Kubernetes dev environment

# ------------------------------------------------------------
# 1️⃣ Minikube helpers
# ------------------------------------------------------------

MINIKUBE ?= minikube

.PHONY: minikube-start minikube-stop

# Start Minikube (Docker driver) – creates the local K8s cluster
minikube-start:
	@echo "Starting Minikube with Docker driver..."
	@$(MINIKUBE) start --driver=docker

# Stop Minikube – shuts down the local VM
minikube-stop:
	@echo "Stopping Minikube..."
	@$(MINIKUBE) stop

# ------------------------------------------------------------
# 2️⃣ Deployment helpers (apply / delete)
# ------------------------------------------------------------

KUBECONFIG ?= $(HOME)/.kube/config

.PHONY: k8s-apply k8s-delete

# Deploy all manifests (namespace, configmap, deployments, services)
k8s-apply:
	@echo "Applying Kubernetes manifests..."
	@kubectl apply -f k8s/namespace.yaml
	@kubectl apply -f k8s/configmap.yaml
	@kubectl apply -f k8s/deployment-processor.yaml
	@kubectl apply -f k8s/service-processor.yaml
	@kubectl apply -f k8s/deployment-gateway.yaml
	@kubectl apply -f k8s/service-gateway.yaml

# Remove everything that was created by `k8s-apply`
k8s-delete:
	@echo "Deleting all Kubernetes resources..."
	@kubectl delete -f k8s/ 2>/dev/null || true

# ------------------------------------------------------------
# 3️⃣ Checks / testing (validation suite)
# ------------------------------------------------------------

# Port used for local gateway health / payment checks (default 8081)
PAYMENT_PORT ?= 8081
# Port used for local processor health / process checks (default 30080)
PROCESSOR_PORT ?= 30080

.PHONY: check-payment check-all k8s-wait \
        check-health check-ready check-processor-health \
        check-payment-success check-invalid-payload check-auth-failure

# -----------------------------------------------------------------
# Simple one‑off payment request (happy path)
# -----------------------------------------------------------------
check-payment:
	@echo "Sending test payment request to gateway on port $(PAYMENT_PORT)..."
	@curl -s -X POST http://localhost:$(PAYMENT_PORT)/pay \
	  -H "Content-Type: application/json" \
	  -H "X-Service-Token: dev-shared-secret-change-me" \
	  -d '{"amount":12345,"currency":"USD","payer":"acc-1","payee":"acc-2","cardNumber":"4111111111111111","expiry":"12/25","cvv":"123","reference":"test-01"}'

# -----------------------------------------------------------------
# Run **all** mandatory checks in sequence
# -----------------------------------------------------------------
check-all: k8s-wait check-health check-ready check-processor-health \
           check-payment-success check-invalid-payload check-auth-failure
	@echo "All mandatory checks passed."

# Wait until both pods are Ready (timeout 60 s each)
k8s-wait:
	@echo "Waiting for gateway and processor pods to become Ready…"
	@kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=payment-gateway \
	  -n payment-system --timeout=60s
	@kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=payment-processor \
	  -n payment-system --timeout=60s

# Gateway /healthz → 200
check-health:
	@echo "Checking gateway /healthz..."
	@curl -s -o /dev/null -w "%{http_code}\n" http://localhost:$(PAYMENT_PORT)/healthz \
	  | grep -q '^200$$' && echo "OK" || (echo "Gateway health check FAILED" && exit 1)

# Gateway /readyz → 200 (processor reachable)
check-ready:
	@echo "Checking gateway /readyz..."
	@curl -s -o /dev/null -w "%{http_code}\n" http://localhost:$(PAYMENT_PORT)/readyz \
	  | grep -q '^200$$' && echo "OK" || (echo "Gateway readiness FAILED" && exit 1)

# Processor /healthz → 200
check-processor-health:
	@echo "Checking processor /healthz on port $(PROCESSOR_PORT)..."
	@curl -s -o /dev/null -w "%{http_code}\n" http://localhost:$(PROCESSOR_PORT)/healthz \
	  | grep -q '^200$$' && echo "OK" || (echo "Processor health check FAILED" && exit 1)

# Happy‑path payment (expects approved status)
check-payment-success:
	@echo "Running happy‑path payment request..."
	@curl -s -X POST http://localhost:$(PAYMENT_PORT)/pay \
	  -H "Content-Type: application/json" \
	  -H "X-Service-Token: dev-shared-secret-change-me" \
	  -d '{"amount":12345,"currency":"USD","payer":"acc-1","payee":"acc-2","cardNumber":"4111111111111111","expiry":"12/25","cvv":"123","reference":"test-01"}' \
	  -o response.json
	@cat response.json | grep -q '"status":"approved"' && echo "Payment succeeded" \
	  || (echo "Payment FAILED" && cat response.json && exit 1)

# Invalid payload → expect HTTP 422
check-invalid-payload:
	@echo "Testing invalid payload (missing payer/payee)..."
	@curl -s -o /dev/null -w "%{http_code}\n" -X POST http://localhost:$(PAYMENT_PORT)/pay \
	  -H "Content-Type: application/json" \
	  -H "X-Service-Token: dev-shared-secret-change-me" \
	  -d '{"amount":12345,"currency":"USD"}' | grep -q '^422$$' && echo "Invalid-payload check OK (422)" || (echo "Invalid-payload check FAILED" && exit 1)

# Processor auth failure (no Bearer token) → expect HTTP 401
check-auth-failure:
	@echo "Testing processor auth failure (no Bearer token)..."
	@curl -s -o /dev/null -w "%{http_code}\n" -X POST http://localhost:$(PROCESSOR_PORT)/process \
	  -H "Content-Type: application/json" \
	  -d '{"amount":12345,"currency":"USD","payer":"acc-1","payee":"acc-2","cardNumber":"4111111111111111","expiry":"12/25","cvv":"123","reference":"test-01"}' | grep -q '^401$$' && echo "Auth-failure check OK (401)" || (echo "Auth-failure check FAILED" && exit 1)

# ------------------------------------------------------------
# 4️⃣ Miscellaneous helpers
# ------------------------------------------------------------

.PHONY: clean

# Remove all K8s resources and stop Minikube (if running)
clean: k8s-delete minikube-stop
	@echo "Cleanup complete."
