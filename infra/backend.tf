terraform {
  backend "gcs" {
    bucket      = "hermes-prototype-aja-tofu-state"
    prefix      = "main"
    credentials = "./bootstrap/tofu-runner-credentials.json"
  }
}
