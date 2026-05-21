provider "google" {
  project     = var.gcp_project_id
  region      = var.gcp_region
  credentials = file(var.gcp_credentials_file)
  alias       = "main"
}

# hcloud provider is configured even when var.cloud = "gcp" because OpenTofu
# evaluates root-level provider blocks unconditionally. When the token variable
# is empty (Hetzner not in use), substitute a 64-char placeholder so the hcloud
# provider passes its shape validation. No Hetzner API calls happen unless the
# Hetzner module is instantiated (count > 0).
provider "hcloud" {
  token = var.hcloud_token != "" ? var.hcloud_token : "0000000000000000000000000000000000000000000000000000000000000000"
  alias = "main"
}
