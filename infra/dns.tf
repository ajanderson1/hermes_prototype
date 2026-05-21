provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

resource "cloudflare_record" "host" {
  zone_id = var.cloudflare_zone_id
  name    = split(".", var.hostname)[0]
  type    = "A"
  value   = local.public_ip
  ttl     = 60
  proxied = false
}
