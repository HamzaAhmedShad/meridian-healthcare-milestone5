terraform {
  required_version = ">= 1.6"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# Short local aliases used across all modules
locals {
  project_id = var.project_id
  region     = var.region
  zone       = var.zone
}
