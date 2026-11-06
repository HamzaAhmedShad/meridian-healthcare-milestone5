# ============================================================
# CLOUD SQL — PostgreSQL instance
# Import with:
#   terraform import google_sql_database_instance.main \
#     meridian-healthcare-cost/SQL_INSTANCE_NAME
# ============================================================

resource "google_sql_database_instance" "main" {
  name             = var.sql_instance_name
  database_version = "POSTGRES_18"
  region           = "us-central1" # instance is in us-central1-f
  project          = var.project_id

  settings {
    tier = "db-f1-micro"

    ip_configuration {
      # Private IP only — matches your Milestone 4 requirement
      # Private address: 10.92.0.3
      ipv4_enabled    = false
      private_network = "projects/${var.project_id}/global/networks/default"
    }

    backup_configuration {
      enabled = true
    }
  }

  deletion_protection = true

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [settings, root_password]
  }
}

# ============================================================
# DATABASE
# Import with:
#   terraform import google_sql_database.main \
#     meridian-healthcare-cost/SQL_INSTANCE_NAME/healthcare_cost
# ============================================================

resource "google_sql_database" "main" {
  name     = "healthcare_cost"
  instance = google_sql_database_instance.main.name
  project  = var.project_id
}

# ============================================================
# DB USER
# Import with:
#   terraform import google_sql_user.app \
#     meridian-healthcare-cost/SQL_INSTANCE_NAME/healthcare_app
# ============================================================

resource "google_sql_user" "app" {
  name     = "healthcare_app"
  instance = google_sql_database_instance.main.name
  project  = var.project_id

  lifecycle {
    # Password managed via Secret Manager — don't let Terraform reset it
    ignore_changes = [password]
  }
}
