#!/usr/bin/env bash
# Prepares the Kind cluster for local Kyverno admission controller development.
# Generates dev TLS certs matching the host IP, updates the Kyverno TLS secrets,
# dumps webhook configurations, scales down the in-cluster controller, waits for
# Kyverno to clean up its webhooks, then re-creates them pointing to the host.
set -euo pipefail

CONTEXT="${CONTEXT:-kind-playground}"
KUBECTL="kubectl --context $CONTEXT"
WORK_DIR="$(cd "$(dirname "$0")" && pwd)/.dev"
WEBHOOK_PORT="${WEBHOOK_PORT:-9443}"

# --- 1. Detect host IP reachable from Kind containers ---
if colima status >/dev/null 2>&1; then
  HOST_IP="host.lima.internal"
  echo " Detected runtime: Colima → host=$HOST_IP"
elif docker info --format '{{.Name}}' 2>/dev/null | grep -qi desktop; then
  HOST_IP="host.docker.internal"
  echo " Detected runtime: Docker Desktop → host=$HOST_IP"
else
  HOST_IP=$(docker network inspect kind -f '{{(index .IPAM.Config 0).Gateway}}' 2>/dev/null || echo "172.17.0.1")
  echo " Detected runtime: unknown → using gateway $HOST_IP"
fi

# --- 2. Extract existing Kyverno CA and generate dev leaf cert ---
# Reuse the CA from kyverno-svc.kube-config secret (has tls.crt + tls.key).
# This way the caBundle already trusted by the API server stays valid.
# We only generate a new leaf cert with SANs that include the host IP.
CA_SECRET="kyverno-svc.kyverno.svc.kyverno-tls-ca"
TLS_SECRET="kyverno-svc.kyverno.svc.kyverno-tls-pair"

mkdir -p "$WORK_DIR/certs"
if [ ! -f "$WORK_DIR/certs/tls.crt" ]; then
  echo " ⏳ Extracting Kyverno CA from secret $CA_SECRET..."
  $KUBECTL -n kyverno get secret "$CA_SECRET" -o jsonpath='{.data.tls\.crt}' | base64 -d > "$WORK_DIR/certs/ca.crt"
  $KUBECTL -n kyverno get secret "$CA_SECRET" -o jsonpath='{.data.tls\.key}' | base64 -d > "$WORK_DIR/certs/ca.key"

  echo " ⏳ Generating dev leaf certificate for $HOST_IP signed by Kyverno CA..."
  cat > "$WORK_DIR/certs/san.cnf" <<EOF
[req]
req_extensions = v3_req
distinguished_name = req_distinguished_name

[req_distinguished_name]
CN = kyverno-dev

[v3_req]
subjectAltName = DNS:${HOST_IP},DNS:localhost,DNS:kyverno-svc,DNS:kyverno-svc.kyverno,DNS:kyverno-svc.kyverno.svc,IP:127.0.0.1
EOF

  openssl genrsa -out "$WORK_DIR/certs/tls.key" 2048 2>/dev/null
  openssl req -new -key "$WORK_DIR/certs/tls.key" -out "$WORK_DIR/certs/tls.csr" \
    -subj "/CN=kyverno-dev" -config "$WORK_DIR/certs/san.cnf" 2>/dev/null
  openssl x509 -req -in "$WORK_DIR/certs/tls.csr" \
    -CA "$WORK_DIR/certs/ca.crt" -CAkey "$WORK_DIR/certs/ca.key" -CAcreateserial \
    -out "$WORK_DIR/certs/tls.crt" -days 365 -sha256 \
    -extensions v3_req -extfile "$WORK_DIR/certs/san.cnf" 2>/dev/null

  # Build full cert chain (leaf + intermediate CA) for TLS serving
  cat "$WORK_DIR/certs/tls.crt" "$WORK_DIR/certs/ca.crt" > "$WORK_DIR/certs/tls-chain.crt"

  # Also extract the root CA for a complete caBundle
  $KUBECTL -n kyverno get secret "$CA_SECRET" -o jsonpath='{.data.ca\.crt}' | base64 -d > "$WORK_DIR/certs/root-ca.crt" 2>/dev/null || true
  # Build full CA bundle (intermediate + root if available)
  if [ -s "$WORK_DIR/certs/root-ca.crt" ]; then
    cat "$WORK_DIR/certs/ca.crt" "$WORK_DIR/certs/root-ca.crt" > "$WORK_DIR/certs/ca-bundle.crt"
  else
    cp "$WORK_DIR/certs/ca.crt" "$WORK_DIR/certs/ca-bundle.crt"
  fi

  echo " ✓ Dev leaf certificate generated in $WORK_DIR/certs/"
else
  echo " ✓ Dev certificates already exist in $WORK_DIR/certs/ (delete to regenerate)"
fi

# --- 3. Update Kyverno TLS secrets with dev leaf cert ---
# Replace the admission controller's TLS pair with our dev cert chain (signed by the same CA).
# Kyverno reads certs from these secrets via --caSecretName and --tlsSecretName.
echo " ⏳ Updating Kyverno TLS secret with dev leaf certificate..."
$KUBECTL -n kyverno create secret tls "$TLS_SECRET" \
  --cert="$WORK_DIR/certs/tls-chain.crt" --key="$WORK_DIR/certs/tls.key" \
  --dry-run=client -o yaml | $KUBECTL apply -f - > /dev/null
echo " ✓ Kyverno TLS secret updated"

# --- 4. Dump webhook configurations before scaling down ---
# Kyverno removes its webhook configurations on shutdown, so we need to
# save them first, then re-create them with our patches after the pod is gone.
DUMP_DIR="$WORK_DIR/webhook-dump"
mkdir -p "$DUMP_DIR"

echo " ⏳ Dumping webhook configurations..."
# The caBundle must contain the full CA chain (intermediate + root) so the
# API server can verify the leaf cert served by the local Kyverno process.
CA_BUNDLE=$(base64 < "$WORK_DIR/certs/ca-bundle.crt" | tr -d '\n')

# Only dump the admission-controller webhook configs (not cleanup or other controllers)
ADMISSION_MUTATING_WEBHOOKS=(
  kyverno-policy-mutating-webhook-cfg
  kyverno-resource-mutating-webhook-cfg
  kyverno-verify-mutating-webhook-cfg
)
ADMISSION_VALIDATING_WEBHOOKS=(
  kyverno-cel-exception-validating-webhook-cfg
  kyverno-exception-validating-webhook-cfg
  kyverno-global-context-validating-webhook-cfg
  kyverno-policy-validating-webhook-cfg
  kyverno-resource-validating-webhook-cfg
)

dump_and_patch_webhook() {
  local resource_type="$1"
  local name="$2"
  $KUBECTL get "$resource_type" "$name" -o json | jq '
    del(.metadata.resourceVersion, .metadata.uid, .metadata.creationTimestamp,
        .metadata.generation, .metadata.managedFields) |
    if (.webhooks // null) != null then
      .webhooks = [.webhooks[] |
        if .clientConfig.service != null then
          .clientConfig.url = "https://'"${HOST_IP}"':'"${WEBHOOK_PORT}"'" + (.clientConfig.service.path // "") |
          .clientConfig.caBundle = "'"${CA_BUNDLE}"'" |
          del(.clientConfig.service)
        else
          .clientConfig.caBundle = "'"${CA_BUNDLE}"'"
        end
      ]
    else
      .
    end
  ' > "$DUMP_DIR/${resource_type}-${name}.json"
  echo "   saved $name"
}

for name in "${ADMISSION_MUTATING_WEBHOOKS[@]}"; do
  dump_and_patch_webhook "mutatingwebhookconfiguration" "$name"
done
for name in "${ADMISSION_VALIDATING_WEBHOOKS[@]}"; do
  dump_and_patch_webhook "validatingwebhookconfiguration" "$name"
done
echo " ✓ Webhook configurations saved to $DUMP_DIR"

# --- 5. Scale down in-cluster admission controller ---
echo " ⏳ Scaling down in-cluster admission controller..."
$KUBECTL -n kyverno scale deployment/kyverno-admission-controller --replicas=0 > /dev/null

# --- 6. Wait for webhook configurations to be removed by Kyverno ---
echo " ⏳ Waiting for Kyverno to clean up its webhook configurations..."
for i in $(seq 1 30); do
  remaining=$($KUBECTL get mutatingwebhookconfigurations -l webhook.kyverno.io/managed-by=kyverno -o name 2>/dev/null | wc -l | tr -d ' ')
  if [ "$remaining" -eq 0 ]; then
    break
  fi
  sleep 2
done
echo " ✓ Webhook configurations removed by Kyverno"

# --- 7. Re-create webhook configurations with host URL patches ---
echo " ⏳ Re-creating webhook configurations pointing to host..."
for f in "$DUMP_DIR"/*.json; do
  [ -f "$f" ] || continue
  $KUBECTL apply -f "$f" > /dev/null
  echo "   applied $(basename "$f" .json)"
done
echo " ✓ Webhook configurations re-created"

# --- 8. Print instructions ---
echo ""
echo "  ┌─────────────────────────────────────────────────────────────"
echo "  │ Kyverno dev mode ready!"
echo "  │"
echo "  │ Host:  ${HOST_IP}:${WEBHOOK_PORT}"
echo "  │ Certs: ${WORK_DIR}/certs/"
echo "  │"
echo "  │ Run the admission controller locally with:"
echo "  │"
echo "  │   go run ./cmd/kyverno/ \\"
echo "  │     --kubeconfig=\$HOME/.kube/config \\"
echo "  │     --serverIP=${HOST_IP} \\"
echo "  │     --webhookServerPort=${WEBHOOK_PORT} \\"
echo "  │     --caSecretName=${CA_SECRET} \\"
echo "  │     --tlsSecretName=${TLS_SECRET}"
echo "  │"
echo "  │ To restore in-cluster Kyverno:  make dev-stop"
echo "  └─────────────────────────────────────────────────────────────"
