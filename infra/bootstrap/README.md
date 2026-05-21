# Bootstrap — one-time GCP project creation

This sub-stack creates the GCP project that the main `infra/` stack will deploy into. Run it **once**, manually, with your gcloud Application Default Credentials.

## Run

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars: set billing_account and project_id
tofu init
tofu apply
```

## Outputs

- A new GCP project with Compute, IAM, Secret Manager APIs enabled.
- A `tofu-runner` service account with the roles the main stack needs.
- A credentials JSON written to `tofu-runner-credentials.json` (gitignored).

## What to do next

1. Encrypt the credentials JSON with age (Task 5 in the P1 plan).
2. Upload the encrypted file to your Hetzner Object Storage bucket.
3. The main `infra/` stack will fetch + decrypt it at apply time.

## Teardown

Only if you're nuking the whole project:

```bash
tofu destroy
```

Note: GCP project deletion is delayed by 30 days. The `deletion_policy = "DELETE"` in `main.tf` opts into immediate scheduling.
