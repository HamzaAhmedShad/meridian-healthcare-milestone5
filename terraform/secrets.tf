# ============================================================
# SECRET MANAGER — DB password secret
# Import with:
#   terraform import google_secret_manager_secret.db_password \
#     projects/meridian-healthcare-cost/secrets/healthcare-db-password
#
# NOTE: Terraform manages the secret *resource* (name, replication policy).
# The actual secret *value* is set manually / by your team and is NOT stored
# in Terraform state for security reasons.
# ============================================================

resource "google_secret_manager_secret" "db_password" {
  secret_id = "healthcare-db-password"
  project   = var.project_id

  replication {
    auto {}
  }

  lifecycle {
    prevent_destroy = true
    # Never let Terraform overwrite the secret value
    ignore_changes = [replication]
  }
}
