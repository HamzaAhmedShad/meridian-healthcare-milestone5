resource "google_logging_metric" "http_5xx_errors" {
  name        = "http_5xx_errors"
  description = "Count of HTTP 500-599 request logs from the healthcare API"
  project     = var.project_id

  filter = <<-EOT
    resource.type="k8s_container"
    resource.labels.project_id="${var.project_id}"
    resource.labels.cluster_name="${var.cluster_name}"
    resource.labels.namespace_name="default"
    resource.labels.container_name="healthcare-api"
    jsonPayload.event="http_request"
    httpRequest.status>=500
    httpRequest.status<600
  EOT

  metric_descriptor {
    metric_kind  = "DELTA"
    value_type   = "INT64"
    unit         = "1"
    display_name = "Healthcare API HTTP 5xx Errors"
  }
}

resource "google_monitoring_notification_channel" "team_email" {
  display_name = "Meridian Team Email"
  type         = "email"
  project      = var.project_id

  labels = {
    email_address = var.alert_email
  }
}

resource "google_monitoring_alert_policy" "http_5xx_spike" {
  display_name = "Healthcare API - HTTP 5xx detected"
  project      = var.project_id
  combiner     = "OR"
  enabled      = true

  conditions {
    display_name = "At least one HTTP 5xx error in 10 minutes"

    condition_threshold {
      filter = <<-EOT
        metric.type="logging.googleapis.com/user/${google_logging_metric.http_5xx_errors.name}"
        resource.type="k8s_container"
        resource.labels.project_id="${var.project_id}"
        resource.labels.cluster_name="${var.cluster_name}"
        resource.labels.namespace_name="default"
        resource.labels.container_name="healthcare-api"
      EOT

      aggregations {
        alignment_period     = "600s"
        per_series_aligner   = "ALIGN_SUM"
        cross_series_reducer = "REDUCE_SUM"
      }

      comparison      = "COMPARISON_GT"
      threshold_value = 0
      duration        = "0s"

      trigger {
        count = 1
      }
    }
  }

  notification_channels = [
    google_monitoring_notification_channel.team_email.name
  ]

  alert_strategy {
    auto_close = "1800s"
  }

  documentation {
    content   = "At least one HTTP 500-599 response was recorded by the healthcare API in a 10-minute window. Inspect API request logs and deployment status. Logs: https://console.cloud.google.com/logs/query?project=${var.project_id}"
    mime_type = "text/markdown"
  }
}

resource "google_monitoring_dashboard" "main" {
  depends_on     = [google_logging_metric.http_5xx_errors]
  project        = var.project_id
  dashboard_json = file("${path.module}/dashboard.json")
}
