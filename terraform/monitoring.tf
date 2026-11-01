# ============================================================
# LOG-BASED METRIC — counts HTTP 5xx errors from the API pods
# The filter matches JSON logs where httpRequest.status >= 500
# emitted by the healthcare-api container in GKE.
# ============================================================

resource "google_logging_metric" "http_5xx_errors" {
  name        = "http_5xx_errors"
  description = "Count of HTTP 5xx responses from the healthcare-api GKE pods"
  project     = var.project_id

  filter = <<-EOT
    resource.type="k8s_container"
    resource.labels.container_name="healthcare-api"
    jsonPayload.httpRequest.status>=500
  EOT

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"
    display_name = "HTTP 5xx Errors"

    labels {
      key         = "status"
      value_type  = "INT64"
      description = "HTTP response status code"
    }
  }

  label_extractors = {
    "status" = "EXTRACT(jsonPayload.httpRequest.status)"
  }
}

# ============================================================
# NOTIFICATION CHANNEL — team email
# After terraform apply, run:
#   terraform output notification_channel_id
# to verify the channel was created.
# ============================================================

resource "google_monitoring_notification_channel" "team_email" {
  display_name = "Meridian Team Email"
  type         = "email"
  project      = var.project_id

  labels = {
    email_address = var.alert_email
  }
}

# ============================================================
# ALERT POLICY — fires when 5xx count > 5 in a 5-minute window
# ============================================================

resource "google_monitoring_alert_policy" "http_5xx_spike" {
  display_name = "HTTP 5xx Error Spike"
  project      = var.project_id
  combiner     = "OR"
  enabled      = true

  conditions {
    display_name = "5xx errors exceed 5 in 5 minutes"

    condition_threshold {
      filter = <<-EOT
        metric.type="logging.googleapis.com/user/http_5xx_errors"
        resource.type="k8s_container"
      EOT

      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
        cross_series_reducer = "REDUCE_SUM"
        group_by_fields    = []
      }

      comparison      = "COMPARISON_GT"
      threshold_value = 5
      duration        = "0s"

      trigger {
        count = 1
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.team_email.name]

  alert_strategy {
    auto_close = "1800s"
  }

  documentation {
    content   = "HTTP 5xx spike detected on the healthcare-api GKE pods. Check Cloud Logging for details: https://console.cloud.google.com/logs"
    mime_type = "text/markdown"
  }
}

# ============================================================
# DASHBOARD — Error count, CPU, Memory, Latency
# ============================================================

resource "google_monitoring_dashboard" "main" {
  project        = var.project_id
  dashboard_json = jsonencode({
    displayName = "Meridian Healthcare — Application Dashboard"
    mosaicLayout = {
      columns = 12
      tiles = [
        # ── Tile 1: HTTP 5xx Error Count ──────────────────────────────────
        {
          width  = 6
          height = 4
          widget = {
            title = "HTTP 5xx Error Count"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "metric.type=\"logging.googleapis.com/user/http_5xx_errors\" resource.type=\"k8s_container\""
                    aggregation = {
                      alignmentPeriod    = "60s"
                      perSeriesAligner   = "ALIGN_RATE"
                      crossSeriesReducer = "REDUCE_SUM"
                    }
                  }
                }
                plotType = "LINE"
              }]
              timeshiftDuration = "0s"
              yAxis = { label = "Errors / sec", scale = "LINEAR" }
            }
          }
        },
        # ── Tile 2: GKE CPU Utilization ───────────────────────────────────
        {
          xPos   = 6
          width  = 6
          height = 4
          widget = {
            title = "GKE Pod CPU Utilization"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "metric.type=\"kubernetes.io/container/cpu/core_usage_time\" resource.type=\"k8s_container\" resource.labels.container_name=\"healthcare-api\""
                    aggregation = {
                      alignmentPeriod    = "60s"
                      perSeriesAligner   = "ALIGN_RATE"
                      crossSeriesReducer = "REDUCE_MEAN"
                      groupByFields      = ["resource.labels.pod_name"]
                    }
                  }
                }
                plotType = "LINE"
              }]
              yAxis = { label = "CPU cores", scale = "LINEAR" }
            }
          }
        },
        # ── Tile 3: GKE Memory Usage ──────────────────────────────────────
        {
          yPos   = 4
          width  = 6
          height = 4
          widget = {
            title = "GKE Pod Memory Usage"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "metric.type=\"kubernetes.io/container/memory/used_bytes\" resource.type=\"k8s_container\" resource.labels.container_name=\"healthcare-api\""
                    aggregation = {
                      alignmentPeriod    = "60s"
                      perSeriesAligner   = "ALIGN_MEAN"
                      crossSeriesReducer = "REDUCE_MEAN"
                      groupByFields      = ["resource.labels.pod_name"]
                    }
                  }
                }
                plotType = "LINE"
              }]
              yAxis = { label = "Bytes", scale = "LINEAR" }
            }
          }
        },
        # ── Tile 4: Active Pod Replicas ───────────────────────────────────
        {
          xPos   = 6
          yPos   = 4
          width  = 6
          height = 4
          widget = {
            title = "Active Pod Replicas (healthcare-api)"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "metric.type=\"kubernetes.io/pod/volume/total_bytes\" resource.type=\"k8s_pod\""
                    aggregation = {
                      alignmentPeriod    = "60s"
                      perSeriesAligner   = "ALIGN_MEAN"
                      crossSeriesReducer = "REDUCE_COUNT"
                      groupByFields      = ["resource.labels.namespace_name"]
                    }
                  }
                }
                plotType = "LINE"
              }]
              yAxis = { label = "Pod count", scale = "LINEAR" }
            }
          }
        }
      ]
    }
  })
}
