#!/usr/bin/env bash
# Runs once cert-manager is `Available`. Mints a Certificate via a SelfSigned
# Issuer and asserts it reaches Ready=True. This is a stronger assertion than
# "Deployments are Available" — it proves the controllers + webhook + cainjector
# chain actually mints certs, which is the whole point of cert-manager.
set -euo pipefail

CLUSTER_NAME="cluster"
env_file="$TEST_TMPDIR/${CLUSTER_NAME}.env"
[[ -f "$env_file" ]] || { echo "missing kind env file" >&2; exit 1; }
# shellcheck disable=SC1090
source "$env_file"

echo "smoke_test: applying SelfSigned Issuer + Certificate"
# cert-manager's webhook briefly refuses connections after Deployment goes
# Available — Service endpoints lag readiness, and CA injection is async.
# Retry the apply for up to 60 s.
deadline=$(( $(date +%s) + 60 ))
while :; do
  if "$KUBECTL" --kubeconfig="$KUBECONFIG" apply -f - <<'EOF' 2>/tmp/apply.err
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: smoke-selfsigned
  namespace: default
spec:
  selfSigned: {}
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: smoke-cert
  namespace: default
spec:
  secretName: smoke-cert-tls
  issuerRef:
    name: smoke-selfsigned
    kind: Issuer
  commonName: smoke.example.com
  dnsNames:
    - smoke.example.com
EOF
  then
    break
  fi
  if (( $(date +%s) >= deadline )); then
    echo "smoke_test: FAIL — Issuer/Certificate apply never accepted by webhook" >&2
    cat /tmp/apply.err >&2
    exit 1
  fi
  echo "smoke_test: webhook not ready yet ($(head -1 /tmp/apply.err)); retrying"
  sleep 2
done

echo "smoke_test: waiting for Certificate Ready"
deadline=$(( $(date +%s) + 60 ))
while (( $(date +%s) < deadline )); do
  ready=$("$KUBECTL" --kubeconfig="$KUBECONFIG" -n default get certificate smoke-cert \
    -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
  if [[ "$ready" == "True" ]]; then
    echo "smoke_test: OK — Certificate smoke-cert Ready=True"
    # Sanity: the secret must actually exist with a tls.crt key.
    "$KUBECTL" --kubeconfig="$KUBECONFIG" -n default get secret smoke-cert-tls \
      -o jsonpath='{.data.tls\.crt}' >/dev/null
    echo "smoke_test: OK — secret/smoke-cert-tls has tls.crt"
    exit 0
  fi
  sleep 1
done

echo "smoke_test: FAIL — Certificate never reached Ready=True" >&2
"$KUBECTL" --kubeconfig="$KUBECONFIG" -n default get certificate smoke-cert -o yaml >&2 || true
exit 1
