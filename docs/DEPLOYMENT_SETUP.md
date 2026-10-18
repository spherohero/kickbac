# Existing deployment — do not provision a duplicate

**Public API:** https://api.kickbac.vodka

The backend is deployed on Nicholas's existing authorized Vultr VM `144.202.38.243` (Ubuntu24.04.5 LTS / Python3.12.3, dedicated `kickbac` user). It uses one loopback FastAPI/uvicorn worker behind Caddy trusted HTTPS, durable SQLite outside releases, supervised restart and daily online SQLite snapshots. Public DNS delegation is verified; see [CLOUDFLARE_DNS.md](CLOUDFLARE_DNS.md).

The previous provisioning/price recommendations in this file are superseded. **Do not buy/create/upgrade a VM, repeat registrar changes or recreate credentials because an old checklist said deployment was pending.** No extra paid resources, top-ups or auto-recharge are authorized by the implementation. Nicholas reported approximately$28/month for the existing VM; account billing/credits are operator-owned, not assumed an enforced cap.

## Current operator references

- [OPERATIONS.md](OPERATIONS.md): installed directory/service/backup layout, release-local locked runtime, explicit backup/migration/update and rollback procedure.
- [PROFILE_VERIFICATION.md](PROFILE_VERIFICATION.md): executed schema3 profile deployment checkpoint, source provenance, tests and limitations.
- [API.md](API.md) and live https://api.kickbac.vodka/openapi.json : application contract. Game/points changes have their own migration and release verification; do not infer live status from a local schema file.

Preserve private `/etc/kickbac` configuration/device credentials and the durable database. Never publish populated environment files, DB/backups or private keys. Device credentials belong to the ESP32/operator, never iOS/NFC/QR.

## Security and acceptance boundaries

- Keep port8000/database private and retain existing SSH access before changing firewall rules. SSH source restriction/cloud-firewall review remains a follow-up; no blind lockout or change to unrelated services.
- Native app uses the public HTTPS origin and Auth0 API access token; the logical audience remains **`https://kickbac-api`** without a slash.
- A server health response or SMS account does not prove real iPhone token/history/profile acceptance. Liam owns native verification; no client files were changed by hosting work.
- NFC/QR resolver returns JSON; Apple associated domains/native app launch are not configured by DNS or Caddy alone.
- Service restart and disk/snapshot persistence were exercised. Actual OS reboot, off-host disaster recovery and sensor calibration are not certified complete. Local snapshots share the VM's failure domain.
- Do not restore an old schema2 snapshot or switch to schema2-only code over a newer DB without an explicit data-preserving rollback plan. Preserve current profiles/readings/game results before a downgrade.

For firmware/hardware use the approved current device contract. The pressure sensor is unavailable; do not fabricate breath duration or BAC to make uploads appear valid.