#!/usr/bin/env bash
set -euo pipefail

# KServe v0.17.0 Installation Script (Standard/Raw Mode)
# Reference: https://kserve.github.io/website/docs/install/kserve-install

KSERVE_VERSION="v0.17.0"

echo "=== 1. Checking Prerequisites (kubectl, helm) ==="
if ! command -v helm &> /dev/null; then
    echo "Error: helm is not installed. Please install helm first."
    exit 1
fi

echo "=== 2. Installing KServe dependencies (Cert-Manager & Istio) ==="
# Using the official quick-install dependency manifest which is tested with v0.17.0
# This is more reliable than manual version guessing.
curl -fsSL https://github.com/kserve/kserve/releases/download/${KSERVE_VERSION}/kserve-standard-mode-full-install-with-manifests.sh | bash

echo ""
echo "=== 3. Verifying Installation ==="
echo "Waiting for KServe controller to be ready..."
kubectl wait --for=condition=ready pod -l 'control-plane=kserve-controller-manager' -n kserve --timeout=300s

echo ""
echo "=== KServe v0.17.0 Standard Mode Setup Complete! ==="
echo "Note: This setup uses Standard mode (no Knative), which is ideal for T2S GPU workloads."
echo "You can now proceed to deploy your InferenceServices in the t2s-system namespace."
