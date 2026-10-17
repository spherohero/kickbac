# Vultr and Cloudflare setup — VM reported, DNS delegation pending

Nicholas reports $100 Vultr credits, VM IPv4 `144.202.38.243`, displayed price approximately$28/month, SSH key selected, no Vultr firewall attached, and registered domain `kickbac.vodka`. Actual VM plan/OS and SSH authentication are not independently inspected; do not provision a duplicate. Recommended upgrade: Shared CPU -> High Performance -> AMD, plan `vhp-2c-4gb-amd`, with 2 vCPUs, 4 GB RAM, 100 GB NVMe disk, advertised $24/month base. The public catalog and Miami availability endpoint list this plan as available. This supersedes the earlier $10/month recommendation; confirm the dashboard's final quote, credit eligibility/expiry and capacity before deploying. No Vultr VM was created by the agent; the VM was supplied by Nicholas. A Cloudflare Free zone and DNS records were created and read back separately (see CLOUDFLARE_DNS.md). This is ample headroom for the initial backend without GPU, managed database or Kubernetes complexity.

## Hosting reference (VM already reported; do not create another)

1. Add an SSH PUBLIC key in Vultr Account -> SSH Keys -> Add SSH Key. A validated ED25519 public key already exists locally at `C:/Users/nicho/.ssh/id_ed25519.pub`, with a matching private-key file on this laptop. Open/copy the `.pub` file only. Never upload/share `id_ed25519` (without `.pub`), paste a private key into chat, or relay its passphrase. Existing key fingerprint: `SHA256:mtp1PCn/DMqKCq8jRkVuSglhhx0U5Y/W8ETh6jQKUdc`. We have not verified agent loading/passphrase availability or remote SSH authentication yet. A dedicated new project key is optional; do not overwrite existing keys.
2. Reference configuration only: the earlier recommendation was ONE Shared CPU -> High Performance -> AMD VM (`vhp-2c-4gb-amd`), not GPU/dedicated/Kubernetes/managed database. Nicholas has now reported provisioning; do not recreate it:
   - Miami, or Atlanta if unavailable.
   - Ubuntu 24.04 LTS x64.
   - 2 vCPUs / 4 GB RAM / 100 GB NVMe disk, public IPv4.
   - Hostname/label `kickbac-api`.
   - Select the uploaded SSH key.
   - No paid add-ons (automatic backups, extra storage or paid DDoS). This is a hackathon demo; durable disk is still required, and application backups remain a deployment task.
   - Confirm the final dashboard quote and credits apply. If the displayed base rate is above $24/month, the intended plan is unavailable, or credits do not apply, STOP and report the quote rather than selecting a larger plan. Read credit expiry/eligibility. Vultr bills hourly and stopped-but-not-destroyed instances remain billable; export needed data then destroy the VM after the project when appropriate. Destroying the VM deletes its data.
3. Attach a Vultr firewall group: TCP22 only from your current public IP (use My IP), TCP80/443 publicly reachable for HTTP challenge/HTTPS. Keep8000 and database ports private. If enabling IPv6, apply equivalent restrictions; don't leave IPv6 as an unrestricted bypass. Moving networks may require updating the SSH source IP. No service should be exposed solely because a firewall allows the port.
4. Report public IP, OS, region, final advertised monthly price and SSH key label/fingerprint. Do not send root passwords, access/API tokens or private keys. Remote host SSH fingerprint and actual BatchMode key authentication must be verified before deployment; never blindly disable host-key checking.

## Domain

Registered domain: `kickbac.vodka`. Planned API origin: `https://api.kickbac.vodka` (NOT yet deployed); the apex can remain available for a later product/landing page. Cloudflare Free zone is now staged with verified A record api.kickbac.vodka ->144.202.38.243,TTL300,DNS-only. Existing apex/wildcard/www parking records were preserved. BOTH assigned Cloudflare nameservers answer the API address directly, but public delegation still uses Porkbun and zone status is pending. Required registrar nameservers are aaden.ns.cloudflare.com and ali.ns.cloudflare.com; replace the old registrar nameservers, not ordinary zone NS records. See CLOUDFLARE_DNS.md for exact steps and verification limits. No registrar changes or IPv6 records were created. Trusted HTTPS still needs to be configured/verified. The Auth0 audience stays `https://kickbac-api`, not the deployed URL.

Liam's bundle ID is `com.liam.KickBAC`. Exact Auth0 callback/logout URL: `com.liam.KickBAC://dev-c87oxm4dkbyatvrn.us.auth0.com/ios/com.liam.KickBAC/callback`. Both allowlists are reported saved and a fresh public request now returns login_required to the URI-equivalent callback (no mismatch); actual user login/logout remain unverified; this is different from the NFC/QR link `https://api.kickbac.vodka/d/kb-demo-01`.

## Report-back template

```text
VM public IPv4:
OS: Ubuntu 24.04 LTS
Region:
Plan / displayed monthly price:
Credits applied: yes/no
SSH public-key label/fingerprint:
Firewall attached (22 My IP, 80/443 public): yes/no
Registered domain: kickbac.vodka
Liam's actual bundle ID: com.liam.KickBAC
Callback/logout URL saved: [URL or pending]
```

Deployment still needs read-only host inspection, isolated service/config/data directories, secret handling, server/proxy startup, trusted certificate, database migration/version/schema readback, reboot persistence, real Auth0 login/user ownership testing, and physical iPhone HTTPS reachability. No one should claim those from public OIDC discovery or local simulated identities.

## Pricing evidence sources
- https://api.vultr.com/v2/plans?per_page=500
- https://api.vultr.com/v2/regions/mia/availability?type=vhp
- https://www.vultr.com/pricing/ (notes region-specific dashboard pricing and paid add-ons)
- https://docs.vultr.com/support/platform/billing/how-am-i-billed-for-my-servers
