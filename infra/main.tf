module "gcp" {
  count  = var.cloud == "gcp" ? 1 : 0
  source = "./modules/gcp"

  providers = {
    google = google.main
  }

  project_id       = var.gcp_project_id
  region           = var.gcp_region
  credentials_file = var.gcp_credentials_file
  hostname         = var.hostname
  machine_type     = var.gcp_machine_type
  ssh_port         = var.ssh_port
  cloud_init       = local.cloud_init_rendered
  operator_cidrs   = var.operator_cidrs
}

module "hetzner" {
  count  = var.cloud == "hetzner" ? 1 : 0
  source = "./modules/hetzner"

  providers = {
    hcloud = hcloud.main
  }

  token          = var.hcloud_token
  hostname       = var.hostname
  location       = var.hcloud_location
  server_type    = var.hcloud_server_type
  ssh_port       = var.ssh_port
  ssh_pubkey     = var.ssh_pubkey
  cloud_init     = local.cloud_init_rendered
  operator_cidrs = var.operator_cidrs
}
