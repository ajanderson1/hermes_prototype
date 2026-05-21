#!/usr/bin/env bash
set -euo pipefail

# Encrypts stack/.env with the age recipient public key. Resulting stack/.env.age
# is what gets scp'd to the VM at /opt/hermes/secrets/.env.age along with the
# matching age private key at /opt/hermes/secrets/age.key.
#
# Pre-processing: docker compose v2 interpolates ${VAR} and $VAR in .env files
# even when consumed via `env_file:`. Bcrypt hashes contain literal '$', so we
# must double every single '$' (except those already doubled). We do this
# transformation in-flight so the source-of-truth .env stays human-readable
# with single '$', and only the encrypted artifact carries doubled '$$'.

RECIPIENT_FILE="$HOME/.config/hermes-prototype/age.recipient"
ENV_FILE="${1:-stack/.env}"

if [[ ! -f "$RECIPIENT_FILE" ]]; then
  echo "missing $RECIPIENT_FILE — generate with: age-keygen -o ~/.config/hermes-prototype/age.key" >&2
  exit 1
fi
if [[ ! -f "$ENV_FILE" ]]; then
  echo "missing $ENV_FILE — create from stack/.env.example" >&2
  exit 1
fi

RECIPIENT="$(grep -oE 'age1[a-z0-9]+' "$RECIPIENT_FILE" | head -1)"
[[ -n "$RECIPIENT" ]] || { echo "could not extract recipient from $RECIPIENT_FILE" >&2; exit 1; }

# Double '$' so compose doesn't interpolate. Implementation: first collapse any
# pre-existing '$$' to '$' to avoid quadrupling, then double every '$'.
TMP_ENV="$(mktemp)"
trap 'rm -f "$TMP_ENV"' EXIT
sed -e 's/\$\$/\$/g' -e 's/\$/$$/g' "$ENV_FILE" > "$TMP_ENV"

OUTPUT="${ENV_FILE}.age"
age --encrypt --recipient "$RECIPIENT" --output "$OUTPUT" "$TMP_ENV"
echo "wrote $OUTPUT (with \$ → \$\$ escape for docker compose)"
echo ""
echo "Next steps:"
echo "  scp -P 2222 $OUTPUT hermes@<VM_IP>:/opt/hermes/secrets/.env.age"
echo "  scp -P 2222 ~/.config/hermes-prototype/age.key hermes@<VM_IP>:/opt/hermes/secrets/age.key"
echo "  ssh -p 2222 hermes@<VM_IP> 'cd /opt/hermes/stack && sudo docker compose up -d'"
