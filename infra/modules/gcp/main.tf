resource "google_compute_network" "main" {
  name                    = "hermes-net"
  auto_create_subnetworks = true
}

resource "google_compute_firewall" "ssh" {
  name    = "hermes-allow-ssh"
  network = google_compute_network.main.name
  allow {
    protocol = "tcp"
    ports    = [tostring(var.ssh_port)]
  }
  source_ranges = var.operator_cidrs
  target_tags   = ["hermes"]
}

resource "google_compute_firewall" "web" {
  name    = "hermes-allow-web"
  network = google_compute_network.main.name
  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["hermes"]
}

resource "google_compute_instance" "main" {
  name         = "hermes-vm"
  machine_type = var.machine_type
  zone         = "${var.region}-a"
  tags         = ["hermes"]

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2404-lts-amd64"
      size  = 40
      type  = "pd-balanced"
    }
  }

  network_interface {
    network = google_compute_network.main.name
    access_config {} # Ephemeral public IP
  }

  metadata = {
    user-data = var.cloud_init
  }

  scheduling {
    automatic_restart   = true
    on_host_maintenance = "MIGRATE"
  }

  service_account {
    scopes = ["cloud-platform"]
  }
}
