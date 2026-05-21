variable "project_id" { type = string }
variable "region" { type = string }
variable "credentials_file" { type = string }
variable "hostname" { type = string }
variable "machine_type" { type = string }
variable "ssh_port" { type = number }
variable "cloud_init" { type = string }
variable "operator_cidrs" { type = list(string) }
