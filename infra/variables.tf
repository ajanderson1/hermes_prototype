variable "cloud" {
  description = "Target cloud: gcp or hetzner"
  type        = string
  validation {
    condition     = contains(["gcp", "hetzner"], var.cloud)
    error_message = "cloud must be 'gcp' or 'hetzner'"
  }
}

variable "hostname" {
  description = "Public hostname (Cloudflare A-record points here)"
  type        = string
}

variable "cloudflare_zone_id" {
  description = "Cloudflare zone ID for the parent domain"
  type        = string
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token with Edit zone DNS scope"
  type        = string
  sensitive   = true
}

variable "ssh_pubkey" {
  description = "SSH public key contents (the whole 'ssh-ed25519 AAAA...' line)"
  type        = string
}

variable "ssh_port" {
  description = "Custom SSH port (not 22)"
  type        = number
  default     = 2222
}

variable "operator_cidrs" {
  description = "CIDRs allowed to SSH and access /mitm /graf /hermes"
  type        = list(string)
}

variable "age_recipient" {
  description = "age public key (recipient) for encrypting secrets"
  type        = string
}

variable "gcp_project_id" {
  description = "GCP project ID (output of bootstrap stack)"
  type        = string
  default     = ""
}

variable "gcp_region" {
  description = "GCP region"
  type        = string
  default     = "europe-west2"
}

variable "gcp_machine_type" {
  description = "GCP machine type"
  type        = string
  default     = "e2-small"
}

variable "gcp_credentials_file" {
  description = "Path to GCP service account credentials JSON"
  type        = string
  default     = "./bootstrap/tofu-runner-credentials.json"
}

variable "hcloud_token" {
  description = "Hetzner Cloud API token"
  type        = string
  default     = ""
  sensitive   = true
}

variable "hcloud_location" {
  description = "Hetzner location"
  type        = string
  default     = "fsn1"
}

variable "hcloud_server_type" {
  description = "Hetzner server type"
  type        = string
  default     = "cpx21"
}
