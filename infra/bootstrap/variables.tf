variable "billing_account" {
  description = "GCP billing account ID (e.g. 01ABCD-23EFGH-45IJKL)"
  type        = string
}

variable "project_id" {
  description = "GCP project ID to create (must be globally unique)"
  type        = string
  default     = "hermes-prototype"
}

variable "project_name" {
  description = "Human-readable project name"
  type        = string
  default     = "Hermes Prototype"
}

variable "org_id" {
  description = "GCP org ID. Leave empty for personal account."
  type        = string
  default     = ""
}

variable "region" {
  description = "Default region for the project"
  type        = string
  default     = "europe-west2"
}
