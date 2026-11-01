variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "GCP zone"
  type        = string
  default     = "us-central1-a"
}

variable "cluster_name" {
  description = "GKE cluster name (fill in after running: gcloud container clusters list)"
  type        = string
}

variable "sql_instance_name" {
  description = "Cloud SQL instance name (fill in after running: gcloud sql instances list)"
  type        = string
}

variable "gcs_bucket_name" {
  description = "GCS upload bucket name"
  type        = string
  default     = "meridian-healthcare-uploads-159331714929"
}

variable "alert_email" {
  description = "Email address to receive alert notifications"
  type        = string
}
