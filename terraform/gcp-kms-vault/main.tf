# adopt existing KMS key ring and crypto key for vault
import {
  to = google_kms_key_ring.vault_key_ring
  id = "projects/${var.project_id}/locations/${var.location}/keyRings/${var.key_ring_name}"
}
import {
  to = google_kms_crypto_key.vault_crypto_key
  id = "projects/${var.project_id}/locations/${var.location}/keyRings/${var.key_ring_name}/cryptoKeys/${var.crypto_key_name}"
}
# Create a Google Cloud KMS Key Ring
resource "google_kms_key_ring" "vault_key_ring" {
  name     = var.key_ring_name
  location = var.location
  project  = var.project_id
}

# Create a Google Cloud KMS Crypto Key
resource "google_kms_crypto_key" "vault_crypto_key" {
  name     = var.crypto_key_name
  key_ring = google_kms_key_ring.vault_key_ring.id
  purpose  = "ENCRYPT_DECRYPT"
  lifecycle {
    prevent_destroy = true
  }
}

# Create a Service Account for Vault to access KMS
resource "google_service_account" "vault_kms_sa" {
  account_id   = var.service_account_name
  display_name = "Service Account for Vault KMS access"
  project      = var.project_id
}

# Grant the Service Account permission to use the Crypto Key

resource "google_kms_crypto_key_iam_member" "vault_kms_sa_member" {
  crypto_key_id = google_kms_crypto_key.vault_crypto_key.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${google_service_account.vault_kms_sa.email}"
}