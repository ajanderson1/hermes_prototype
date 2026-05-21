provider "google" {
  project     = var.gcp_project_id
  region      = var.gcp_region
  credentials = file(var.gcp_credentials_file)
  alias       = "main"
}

provider "hcloud" {
  token = var.hcloud_token
  alias = "main"
}
