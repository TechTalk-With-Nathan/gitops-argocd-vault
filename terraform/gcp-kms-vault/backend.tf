terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "7.12.0"
    }
  }
  backend "gcs" {
    prefix = "kms-vault/state"
  }
}

provider "google" {
  project = var.project_id
}
