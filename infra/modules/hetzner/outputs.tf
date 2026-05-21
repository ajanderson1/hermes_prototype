output "public_ip" {
  value = hcloud_server.main.ipv4_address
}

output "ssh_target" {
  value = "hermes@${hcloud_server.main.ipv4_address}"
}

output "location" {
  value = hcloud_server.main.location
}
