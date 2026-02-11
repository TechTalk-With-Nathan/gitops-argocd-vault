output "vault_kms_sa_email" {
  description = "Vault KMS Service Account Email"
  sensitive   = true
  value       = google_service_account.vault_kms_sa.email
}