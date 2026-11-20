# Makefile for local Kubernetes dev environment

# Choose the desired local cluster (kind or minikube). Default: kind.
MINIKUBE ?= minikube

KUBECONFIG ?= $(HOME)/.kube/config

.PHONY: kind-create kind-delete minikube-start minikube-stop k8s-apply k8s-delete clean check-payment

# Port used for local gateway health/payment check (default 8081)
PAYMENT_PORT ?= 8081

check-payment:
	@echo "Sending test payment request to gateway on port $(PAYMENT_PORT)..."
	@curl -s -X POST http://localhost:$(PAYMENT_PORT)/pay \
	  -H "Content-Type: application/json" \
	  -H "X-Service-Token: dev-shared-secret-change-me" \
	  -d '{"amount":12345,"currency":"USD","payer":"acc-1","payee":"acc-2","cardNumber":"4111111111111111","expiry":"12/25","cvv":"123","reference":"test-01"}'

## Kind helpers
kind-create:
	@echo "Creating Kind cluster '$(KIND_CLUSTER)'..."
	kind create cluster --name $(KIND_CLUSTER) --wait 60s
	kubectl config use-context kind-$(KIND_CLUSTER)

kind-delete:
	@echo "Deleting Kind cluster '$(KIND_CLUSTER)'..."
	kind delete cluster --name $(KIND_CLUSTER)

## Minikube helpers (optional)
minikube-start:
	@echo "Starting Minikube..."
	$(MINIKUBE) start --driver=docker

minikube-stop:
	@echo "Stopping Minikube..."
	minikube stop

## Deploy manifests
k8s-apply:
	kubectl apply -f k8s/namespace.yaml
	kubectl apply -f k8s/configmap.yaml
	kubectl apply -f k8s/deployment-processor.yaml
	kubectl apply -f k8s/service-processor.yaml
	kubectl apply -f k8s/deployment-gateway.yaml
	kubectl apply -f k8s/service-gateway.yaml

k8s-delete:
	kubectl delete -f k8s/ 2>/dev/null || true

clean: k8s-delete kind-delete
	@echo "Cleanup complete."
