locals {
  healthcare_api_principal = "principal://iam.googleapis.com/projects/159331714929/locations/global/workloadIdentityPools/${var.project_id}.svc.id.goog/subject/ns/default/sa/healthcare-api-sa"
}

resource "google_secret_manager_secret_iam_member" "secret_accessor" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.db_password.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = local.healthcare_api_principal
}

resource "google_storage_bucket_iam_member" "uploads_writer" {
  bucket = google_storage_bucket.uploads.name
  role   = "roles/storage.objectCreator"
  member = local.healthcare_api_principal
}

resource "google_service_account" "ci_deployer" {
  account_id   = "ci-deployer"
  display_name = "GitHub Actions CI/CD Deployer"
  project      = var.project_id

  lifecycle {
    prevent_destroy = true
  }
}
