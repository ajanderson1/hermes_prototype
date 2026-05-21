locals {
  cloud_init_rendered = templatefile("${path.module}/cloud-init/userdata.yaml.tftpl", {
    ssh_port      = var.ssh_port
    ssh_pubkey    = var.ssh_pubkey
    hostname      = var.hostname
    age_recipient = var.age_recipient
    repo_url      = "https://github.com/ajanderson1/hermes_prototype.git"
    repo_ref      = "main"
  })

  public_ip = coalesce(
    try(module.gcp[0].public_ip, ""),
    try(module.hetzner[0].public_ip, ""),
  )

  ssh_target = coalesce(
    try(module.gcp[0].ssh_target, ""),
    try(module.hetzner[0].ssh_target, ""),
  )
}
