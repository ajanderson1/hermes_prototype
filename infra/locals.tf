locals {
  cloud_init_rendered = templatefile("${path.module}/cloud-init/userdata.yaml.tftpl", {
    ssh_port      = var.ssh_port
    ssh_pubkey    = var.ssh_pubkey
    hostname      = var.hostname
    age_recipient = var.age_recipient
    repo_url      = "https://github.com/ajanderson1/hermes_prototype.git"
    repo_ref      = "main"
  })
}
