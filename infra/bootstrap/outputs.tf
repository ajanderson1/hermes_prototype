output "project_id" {
  value = google_project.main.project_id
}

output "service_account_email" {
  value = google_service_account.tofu.email
}

output "credentials_file" {
  value     = local_sensitive_file.tofu_credentials.filename
  sensitive = true
}
