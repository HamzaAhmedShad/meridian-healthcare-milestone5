# ============================================================
# SERVICE ACCOUNT — used by GKE pods (Workload Identity)
# Import with:
#   terraform import google_service_account.healthcare_api \
#     projects/meridian-healthcare-cost/serviceAccounts/healthcare-api-sa@meridian-healthcare-cost.iam.gserviceaccount.com
# (adjust the SA email to match yours — check: gcloud iam service-accounts list)
# ============================================================

resource "google_service_account" "healthcare_api" {
  account_id   = "healthcare-api-sa"
  display_name = "Healthcare API Service Account"
  project      = var.project_id
}

# ============================================================
# IAM BINDINGS
# ============================================================

# Allow pods to read secrets
resource "google_project_iam_member" "secret_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.healthcare_api.email}"
}

# Allow pods to read/write GCS upload bucket
resource "google_storage_bucket_iam_member" "uploads_writer" {
  bucket = google_storage_bucket.uploads.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.healthcare_api.email}"
}

# Workload Identity binding — links Kubernetes SA to GCP SA
# The K8s SA name must match serviceAccountName in backend.yaml
resource "google_service_account_iam_member" "workload_identity" {
  service_account_id = google_service_account.healthcare_api.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[default/healthcare-api-sa]"
}

# ============================================================
# CI/CD SERVICE ACCOUNT — used by GitHub Actions
# Import with:
#   terraform import google_service_account.ci_deployer \
#     projects/meridian-healthcare-cost/serviceAccounts/ci-deployer@meridian-healthcare-cost.iam.gserviceaccount.com
# (If it doesn't exist yet, Terraform will create it)
# ============================================================

resource "google_service_account" "ci_deployer" {
  account_id   = "ci-deployer"
  display_name = "GitHub Actions CI/CD Deployer"
  project      = var.project_id
}

resource "google_project_iam_member" "ci_gke_developer" {
  project = var.project_id
  role    = "roles/container.developer"
  member  = "serviceAccount:${google_service_account.ci_deployer.email}"
}

resource "google_project_iam_member" "ci_artifact_writer" {
  project = var.project_id
  role    = "roles/artifactregistry.writer"
  member  = "serviceAccount:${google_service_account.ci_deployer.email}"
}
