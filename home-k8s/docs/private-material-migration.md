# Private and secret material migration checklist

This migration was completed manually. Codex did not upload any item to
Bitwarden. The local owner-only source files were retained until retrieval from
Bitwarden had been tested.

## Completed checks

- [x] Attached the existing Talos `secrets.yaml` to the Bitwarden secure note
  `home-k8s / Talos secrets` with the attachment name `secrets.yaml`. This is
  cryptographic secret material and can exceed the Notes-field size limit.
- [x] Attached `talos/private/home-k8s-prod-red-private.yaml` to the Bitwarden
  secure note `home-k8s / Talos private inventory /
  home-k8s-prod-red-private.yaml`, retaining the exact attachment filename.
- [x] Attached `talos/private/home-k8s-prod-green-private.yaml` to the Bitwarden
  secure note `home-k8s / Talos private inventory /
  home-k8s-prod-green-private.yaml`, retaining the exact attachment filename.
- [x] Confirmed each Bitwarden item can be retrieved as the original raw YAML
  without printing it in a shared terminal or saving it in the checkout.
- [x] Ran `nix develop --command scripts/recovery-prepare --output-dir
  .recovery/retrieval-test` and confirm it validates without applying a config.
- [x] After verification, removed the local `*-private.yaml` files and any
  `.recovery/` output with an approved secure local process.

The two private YAML files are hardware inventory, not credentials. Do not
store them in the same Bitwarden item as `secrets.yaml`; keeping that boundary
prevents operational metadata from being handled as cryptographic secret
material.
