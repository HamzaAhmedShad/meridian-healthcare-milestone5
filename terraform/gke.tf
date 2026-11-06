# ============================================================
# GKE CLUSTER
# Import with:
#   terraform import google_container_cluster.main \
#     meridian-healthcare-cost/us-central1/CLUSTER_NAME
# ============================================================

resource "google_container_cluster" "main" {
  name     = var.cluster_name
  location = var.zone # us-central1-a — this is a ZONAL cluster
  project  = var.project_id

  # We manage the node pool separately; remove the default one.
  initial_node_count = 1

  # Enables Workload Identity — required for GCS/Secret Manager access
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # Keep whatever network/subnetwork you already have
  networking_mode = "VPC_NATIVE"

  ip_allocation_policy {}

  lifecycle {
    # Prevent Terraform from destroying the live cluster accidentally
    prevent_destroy = true
    # Ignore fields that GCP auto-manages so plan stays clean
    ignore_changes = [
      node_config,
      initial_node_count,
      master_auth,
      addons_config,
    ]
  }
}

# ============================================================
# GKE NODE POOL
# Import with:
#   terraform import google_container_node_pool.main \
#     meridian-healthcare-cost/us-central1/CLUSTER_NAME/NODEPOOL_NAME
# (run: gcloud container node-pools list --cluster=CLUSTER_NAME --region=us-central1)
# ============================================================

resource "google_container_node_pool" "main" {
  name       = "default-pool"
  cluster    = google_container_cluster.main.name
  location   = var.zone # must match cluster location (zonal)
  project    = var.project_id
  node_count = 2

  node_config {
    machine_type = "e2-standard-2"

    # Workload Identity on each node
    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]
  }

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [node_count, node_config]
  }
}
