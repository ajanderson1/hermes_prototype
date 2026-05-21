provider "google" {
  region = var.region
}

resource "google_project" "main" {
  name            = var.project_name
  project_id      = var.project_id
  billing_account = var.billing_account
  org_id          = var.org_id == "" ? null : var.org_id
  deletion_policy = "DELETE"
}

resource "google_project_service" "apis" {
  for_each = toset([
    "compute.googleapis.com",
    "iam.googleapis.com",
    "secretmanager.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "serviceusage.googleapis.com",
  ])
  project            = google_project.main.project_id
  service            = each.key
  disable_on_destroy = false
}

resource "google_service_account" "tofu" {
  project      = google_project.main.project_id
  account_id   = "tofu-runner"
  display_name = "OpenTofu runner for hermes-prototype"
  depends_on   = [google_project_service.apis]
}

resource "google_project_iam_member" "tofu_compute_admin" {
  project = google_project.main.project_id
  role    = "roles/compute.admin"
  member  = "serviceAccount:${google_service_account.tofu.email}"
}

resource "google_project_iam_member" "tofu_sa_user" {
  project = google_project.main.project_id
  role    = "roles/iam.serviceAccountUser"
  member  = "serviceAccount:${google_service_account.tofu.email}"
}

resource "google_project_iam_member" "tofu_secret_admin" {
  project = google_project.main.project_id
  role    = "roles/secretmanager.admin"
  member  = "serviceAccount:${google_service_account.tofu.email}"
}

resource "google_service_account_key" "tofu" {
  service_account_id = google_service_account.tofu.name
  public_key_type    = "TYPE_X509_PEM_FILE"
  private_key_type   = "TYPE_GOOGLE_CREDENTIALS_FILE"
}

resource "local_sensitive_file" "tofu_credentials" {
  content         = base64decode(google_service_account_key.tofu.private_key)
  filename        = "${path.module}/tofu-runner-credentials.json"
  file_permission = "0600"
}
