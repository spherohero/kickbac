# Cloudflare DNS — current verified configuration

## Current state

Public delegation to Cloudflare is verified. A fresh query through `1.1.1.1` during backend publication returned:

```text
kickbac.vodka NS aaden.ns.cloudflare.com
kickbac.vodka NS ali.ns.cloudflare.com
api.kickbac.vodka A 144.202.38.243
```

**No further registrar nameserver change is pending.** The registrar remains Porkbun; the two NS values are registrar delegation, not ordinary records to add inside the zone.

The live API is **https://api.kickbac.vodka**, with trusted origin HTTPS through Caddy. Health and OpenAPI were independently verified publicly. Do not follow older notes telling you to recreate the zone, repeat a nameserver switch, or treat the public API as a parking page.

## Records and boundaries

- Cloudflare **Free Website** plan was selected/read back; no paid DNS subscription/domain transfer was created.
- API record: `A api.kickbac.vodka -> 144.202.38.243`, TTL300, **DNS-only** (`proxied=false`) at creation/readback.
- Existing unrelated parking records were preserved: apex A `207.207.210.107` and `207.207.210.229`; wildcard and www CNAMEs to `pixie.porkbun.com`. Do not repurpose them without inspecting the user's current services.
- No Cloudflare Access login, browser challenge, API caching rule or CORS workaround was added. Auth0 audience remains `https://kickbac-api`, not the public hostname.
- DNSSEC was disabled with no parent DS observed at the migration checkpoint. Recheck signing/delegation before any later DNSSEC change.
- Public delegation/A resolution and trusted HTTPS are verified separately from Cloudflare's dashboard zone status; a historical API `pending` label was not freshly read back as `Active`. That does not justify repeating the working registrar migration.

## Hosting and native links

See [OPERATIONS.md](OPERATIONS.md) for the existing Ubuntu VM, private loopback API, Caddy, persistent SQLite and online snapshots. Preserve SSH access when reviewing host/cloud firewall policy; don't expose port8000 or the database. No new VM is required.

`https://api.kickbac.vodka/d/kb-demo-01` is a public **JSON resolver**, not a configured iOS Universal Link. Device resolution, Auth0's custom-scheme callback, native NFC/QR app launch and authenticated arming are distinct flows. Liam owns the client-side link handling.

## Sources

- https://developers.cloudflare.com/dns/zone-setups/full-setup/setup/
- https://developers.cloudflare.com/dns/manage-dns-records/how-to/create-dns-records/
- https://kb.porkbun.com/article/22-how-to-change-your-nameservers