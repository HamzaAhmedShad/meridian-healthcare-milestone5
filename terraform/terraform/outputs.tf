output "gke_cluster_name" {
  description = "GKE cluster name"
  value       = google_container_cluster.main.name
}

output "gke_cluster_endpoint" {
  description = "GKE cluster endpoint"
  value       = google_container_cluster.main.endpoint
  sensitive   = true
}

output "sql_instance_connection_name" {
  description = "Cloud SQL connection name"
  value       = google_sql_database_instance.main.connection_name
}

output "gcs_bucket_name" {
  description = "GCS upload bucket name"
  value       = google_storage_bucket.uploads.name
}

output "notification_channel_id" {
  description = "Monitoring notification channel ID"
  value       = google_monitoring_notification_channel.team_email.name
}

output "ci_deployer_email" {
  description = "GitHub Actions service account email"
  value       = google_service_account.ci_deployer.email
}
