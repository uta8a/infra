# Private Talos hardware inventory

This directory contains templates for machine-specific, non-credential data
that must not be published. At present that is the install-disk serial for the
physical nodes.

The actual `*-private.yaml` files are ignored by Git. Keep each file
owner-readable only, save it as an attachment in Bitwarden under `home-k8s /
Talos private inventory`, and do not delete the local copy until a human has
verified it can be retrieved from Bitwarden.

`scripts/recovery-prepare` retrieves these files from Bitwarden and applies
them as additional Talos config patches. They are deliberately separate from
`secrets.yaml`: a disk serial is private inventory, not cryptographic secret
material.
