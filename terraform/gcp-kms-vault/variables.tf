variable "project_id" {
  description = "GCP project ID where KMS and SA will live"
  type        = string
}

variable "location" {
  description = "GCP location for KMS keyring"
  type        = string
  default     = "global"
}
variable "key_ring_name" {
  description = "Name of the KMS key ring"
  type        = string
}
variable "crypto_key_name" {
  description = "Name of the KMS crypto key"
  type        = string
}
variable "service_account_name" {
  description = "Name of the service account to be created"
  type        = string
}