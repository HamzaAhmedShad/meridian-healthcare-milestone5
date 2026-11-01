#!/usr/bin/env bash
# =============================================================
# Milestone 6 — Terraform Import Script
#
# Run this ONCE from the terraform/ directory to adopt your
# existing GCP resources into Terraform state.
#
# Prerequisites:
#   1. Fill in terraform.tfvars with your real cluster_name and sql_instance_name
#   2. Run: terraform init
#   3. Run: gcloud auth application-default login
#   4. Then run: bash import.sh
# =============================================================

set -euo pipefail

PROJECT_ID="meridian-healthcare-cost"
REGION="us-central1"
ZONE="us-central1-a"
CLUSTER_NAME="healthcare-gke"

# ── Read values from tfvars ───────────────────────────────────────────────────
CLUSTER_NAME=$(grep 'cluster_name' terraform.tfvars | cut -d'"' -f2)SQL_INSTANCE=$(grep 'sql_instance_name' terraform.tfvars | cut -d'"' -f2)
GCS_BUCKET=$(grep 'gcs_bucket_name' terraform.tfvars | cut -d'"' -f2)

# Get your node pool name automatically
NODE_POOL=$(gcloud container node-pools list \
  --cluster="$CLUSTER_NAME" \
  --zone="$ZONE" \
  --format="value(name)" \
  | head -1)

# Get your CI service account (if it already exists)
CI_SA_EMAIL="ci-deployer@${PROJECT_ID}.iam.gserviceaccount.com"
APP_SA_EMAIL="healthcare-api-sa@${PROJECT_ID}.iam.gserviceaccount.com"

echo "=========================================="
echo "Importing existing GCP resources into Terraform state"
echo "Project:      $PROJECT_ID"
echo "Cluster:      $CLUSTER_NAME (zone: $ZONE)"
echo "Node pool:    $NODE_POOL"
echo "SQL instance: $SQL_INSTANCE"
echo "GCS bucket:   $GCS_BUCKET"
echo "=========================================="

# ── GKE ──────────────────────────────────────────────────────────────────────
echo ""
echo "► Importing GKE cluster..."
terraform import google_container_cluster.main "${PROJECT_ID}/${ZONE}/${CLUSTER_NAME}"

echo "► Importing GKE node pool..."
terraform import google_container_node_pool.main "${PROJECT_ID}/${ZONE}/${CLUSTER_NAME}/${NODE_POOL}"

# ── Cloud SQL ─────────────────────────────────────────────────────────────────
echo ""
echo "► Importing Cloud SQL instance..."
terraform import google_sql_database_instance.main "${PROJECT_ID}/${SQL_INSTANCE}"

echo "► Importing Cloud SQL database..."
terraform import google_sql_database.main "${PROJECT_ID}/${SQL_INSTANCE}/healthcare_cost"

echo "► Importing Cloud SQL user..."
terraform import google_sql_user.app "${PROJECT_ID}/${SQL_INSTANCE}/healthcare_app"

# ── GCS ───────────────────────────────────────────────────────────────────────
echo ""
echo "► Importing GCS bucket..."
terraform import google_storage_bucket.uploads "${PROJECT_ID}/${GCS_BUCKET}"

# ── Secret Manager ────────────────────────────────────────────────────────────
echo ""
echo "► Importing Secret Manager secret..."
terraform import google_secret_manager_secret.db_password \
  "projects/${PROJECT_ID}/secrets/healthcare-db-password"

# ── Service Accounts ──────────────────────────────────────────────────────────
echo ""
echo "► Importing app service account..."
terraform import google_service_account.healthcare_api \
  "projects/${PROJECT_ID}/serviceAccounts/${APP_SA_EMAIL}" 2>/dev/null || \
  echo "  (healthcare-api-sa not found — Terraform will create it)"

echo "► Importing CI deployer service account..."
terraform import google_service_account.ci_deployer \
  "projects/${PROJECT_ID}/serviceAccounts/${CI_SA_EMAIL}" 2>/dev/null || \
  echo "  (ci-deployer not found — Terraform will create it)"

echo ""
echo "=========================================="
echo "Import complete! Now run:"
echo "  terraform plan"
echo "It should show no changes for imported resources"
echo "and only additions for new monitoring resources."
echo "=========================================="
