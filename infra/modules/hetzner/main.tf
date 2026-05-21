provider "hcloud" {
  token = var.token
}

resource "hcloud_ssh_key" "main" {
  name       = "hermes-prototype"
  public_key = var.ssh_pubkey
}

resource "hcloud_firewall" "main" {
  name = "hermes-fw"

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = tostring(var.ssh_port)
    source_ips = var.operator_cidrs
  }
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "80"
    source_ips = ["0.0.0.0/0", "::/0"]
  }
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "443"
    source_ips = ["0.0.0.0/0", "::/0"]
  }
}

resource "hcloud_server" "main" {
  name         = "hermes-vm"
  image        = "ubuntu-24.04"
  server_type  = var.server_type
  location     = var.location
  ssh_keys     = [hcloud_ssh_key.main.id]
  user_data    = var.cloud_init
  firewall_ids = [hcloud_firewall.main.id]
}
