output "public_ip" {
  value = local.public_ip
}

output "hostname" {
  value = var.hostname
}

output "ssh_command" {
  value = "ssh -p ${var.ssh_port} ${local.ssh_target}"
}

output "selected_cloud" {
  value = var.cloud
}
