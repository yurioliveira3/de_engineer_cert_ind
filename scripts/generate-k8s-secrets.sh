#!/usr/bin/env bash
# Lê .env e gera k8s/secrets.yaml com todos os valores em base64.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

[ -f "$ROOT/.env" ] || { echo "ERRO: .env não encontrado. Copie .env.example para .env e preencha."; exit 1; }

set -a; source "$ROOT/.env"; set +a

b64() { printf '%s' "$1" | python3 -c "import base64,sys; print(base64.b64encode(sys.stdin.buffer.read()).decode(), end='')"; }

DW_CONN="postgresql://${DW_POSTGRES_USER}:${DW_POSTGRES_PASSWORD}@dw-postgres:5432/analytics_dw"
SRC_CONN="postgresql://${SOURCE_POSTGRES_USER}:${SOURCE_POSTGRES_PASSWORD}@source-postgres:5432/banvic"
META_CONN="postgresql+psycopg2://${AIRFLOW_DB_USER}:${AIRFLOW_DB_PASSWORD}@airflow-db:5432/airflow"

cat > "$ROOT/k8s/secrets.yaml" << EOF
# Gerado por scripts/generate-k8s-secrets.sh — não edite manualmente.
# NUNCA versione este arquivo.
apiVersion: v1
kind: Secret
metadata:
  name: banvic-secrets
  namespace: banvic
type: Opaque
data:
  SOURCE_POSTGRES_USER: $(b64 "$SOURCE_POSTGRES_USER")
  SOURCE_POSTGRES_PASSWORD: $(b64 "$SOURCE_POSTGRES_PASSWORD")
  DW_POSTGRES_USER: $(b64 "$DW_POSTGRES_USER")
  DW_POSTGRES_PASSWORD: $(b64 "$DW_POSTGRES_PASSWORD")
  AIRFLOW_DB_USER: $(b64 "$AIRFLOW_DB_USER")
  AIRFLOW_DB_PASSWORD: $(b64 "$AIRFLOW_DB_PASSWORD")
  AIRFLOW_FERNET_KEY: $(b64 "$AIRFLOW_FERNET_KEY")
  webserver-secret-key: $(b64 "$AIRFLOW__WEBSERVER__SECRET_KEY")
  AIRFLOW_ADMIN_PASSWORD: $(b64 "$AIRFLOW_ADMIN_PASSWORD")
  AIRFLOW_CONN_DW_POSTGRES: $(b64 "$DW_CONN")
  AIRFLOW_CONN_SOURCE_POSTGRES: $(b64 "$SRC_CONN")
---
apiVersion: v1
kind: Secret
metadata:
  name: airflow-metadata-secret
  namespace: banvic
type: Opaque
data:
  connection: $(b64 "$META_CONN")
EOF

echo "OK: k8s/secrets.yaml gerado a partir de .env"
