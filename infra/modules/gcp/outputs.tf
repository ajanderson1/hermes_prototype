output "public_ip" {
  value = google_compute_instance.main.network_interface[0].access_config[0].nat_ip
}

output "ssh_target" {
  value = "hermes@${google_compute_instance.main.network_interface[0].access_config[0].nat_ip}"
}

output "zone" {
  value = google_compute_instance.main.zone
}
