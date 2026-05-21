cloud    = "gcp"
hostname = "hermes.example.com"

cloudflare_zone_id   = "<your-cloudflare-zone-id>"
cloudflare_api_token = "<your-cloudflare-token>"   # or use env: TF_VAR_cloudflare_api_token

ssh_pubkey     = "ssh-ed25519 AAAA... hermes-prototype-vm"
ssh_port       = 2222
operator_cidrs = ["203.0.113.42/32"]   # your home IP, /32

age_recipient = "age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"

# GCP
gcp_project_id       = "hermes-prototype-aja"
gcp_region           = "europe-west2"
gcp_machine_type     = "e2-small"
gcp_credentials_file = "./bootstrap/tofu-runner-credentials.json"

# Hetzner
hcloud_token       = "<hetzner-token>"   # or use env: TF_VAR_hcloud_token
hcloud_location    = "fsn1"
hcloud_server_type = "cpx21"
