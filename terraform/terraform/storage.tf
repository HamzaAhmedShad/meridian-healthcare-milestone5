# ============================================================
# GCS UPLOAD BUCKET
# Import with:
#   terraform import google_storage_bucket.uploads \
#     meridian-healthcare-cost/meridian-healthcare-uploads-159331714929
# ============================================================

resource "google_storage_bucket" "uploads" {
  name          = var.gcs_bucket_name
  location      = var.region
  project       = var.project_id
  force_destroy = false

  uniform_bucket_level_access = true

  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type = "Delete"
    }
  }

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [cors, website]
  }
}
