variable "token" {
  type      = string
  sensitive = true
}
variable "hostname" { type = string }
variable "location" { type = string }
variable "server_type" { type = string }
variable "ssh_port" { type = number }
variable "ssh_pubkey" { type = string }
variable "cloud_init" { type = string }
variable "operator_cidrs" { type = list(string) }
