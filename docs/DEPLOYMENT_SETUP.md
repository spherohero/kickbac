# Vultr and domain setup — proposed, not yet provisioned

Nicholas reports $100 Vultr credits visible and no VM/domain. Credit balance is not unlimited spending approval. No cloud resources were created by the agent. Public Vultr plans/region-availability endpoints currently list `vc2-1c-2gb` in Miami: 1 vCPU, 2048 MB RAM, 55 GB disk, advertised $10/month base. Dashboard pricing/credit application and actual capacity must be confirmed at deployment. The $5/month 1 GB option also exists; 2 GB provides headroom without a managed database or Kubernetes.

## User actions

1. Add an SSH PUBLIC key in Vultr Account -> SSH Keys -> Add SSH Key. A validated ED25519 public key already exists locally at `C:/Users/nicho/.ssh/id_ed25519.pub`, with a matching private-key file on this laptop. Open/copy the `.pub` file only. Never upload/share `id_ed25519` (without `.pub`), paste a private key into chat, or relay its passphrase. Existing key fingerprint: `SHA256:mtp1PCn/DMqKCq8jRkVuSglhhx0U5Y/W8ETh6jQKUdc`. We have not verified agent loading/passphrase availability or remote SSH authentication yet. A dedicated new project key is optional; do not overwrite existing keys.
2. If comfortable with the advertised $10/month base rate, create ONE regular/shared Cloud Compute VM (`vc2-1c-2gb`), not GPU/dedicated/Kubernetes/managed database:
   - Miami, or Atlanta if unavailable.
   - Ubuntu 24.04 LTS x64.
   - 1 vCPU / 2 GB RAM / 55 GB disk, public IPv4.
   - Hostname/label `kickbac-api`.
   - Select the uploaded SSH key.
   - No paid add-ons (automatic backups, extra storage or paid DDoS). This is a hackathon demo; durable disk is still required, and application backups remain a deployment task.
   - Confirm the final dashboard quote and credits apply. If the displayed base rate is above $10/month, the intended plan is unavailable, or credits do not apply, STOP and report the quote rather than selecting a larger plan. Read credit expiry/eligibility and remember a stopped VM may still incur charges; deprovision explicitly after the project when appropriate.
3. Attach a Vultr firewall group: TCP22 only from your current public IP (use My IP), TCP80/443 publicly reachable for HTTP challenge/HTTPS. Keep8000 and database ports private. If enabling IPv6, apply equivalent restrictions; don't leave IPv6 as an unrestricted bypass. Moving networks may require updating the SSH source IP. No service should be exposed solely because a firewall allows the port.
4. Report public IP, OS, region, final advertised monthly price and SSH key label/fingerprint. Do not send root passwords, access/API tokens or private keys. Remote host SSH fingerprint and actual BatchMode key authentication must be verified before deployment; never blindly disable host-key checking.

## Domain

Redeem the event GoDaddy credit only if eligible registration is actually covered by the promotion; do not infer eligibility or availability from a brand suggestion. Choose a domain you want, confirm checkout costs/renewal terms, and skip paid hosting/SSL/website-builder extras. A domain is useful but not required for local development. Send only the registered domain. Do not change nameservers or existing DNS records yet; after the VM IP is verified, use a dedicated `api.<domain>` A record and trusted HTTPS. The Auth0 audience remains `https://kickbac-api` regardless of hostname.

## Report-back template

```text
VM public IPv4:
OS: Ubuntu 24.04 LTS
Region:
Plan / displayed monthly price:
Credits applied: yes/no
SSH public-key label/fingerprint:
Firewall attached (22 My IP, 80/443 public): yes/no
Registered domain: [domain or pending]
Liam's actual bundle ID: [ID or pending]
Callback/logout URL saved: [URL or pending]
```

Deployment still needs read-only host inspection, isolated service/config/data directories, secret handling, server/proxy startup, trusted certificate, database migration/version/schema readback, reboot persistence, real Auth0 login/user ownership testing, and physical iPhone HTTPS reachability. No one should claim those from public OIDC discovery or local simulated identities.

## Pricing evidence sources
- https://api.vultr.com/v2/plans?per_page=500
- https://api.vultr.com/v2/regions/mia/availability?type=vc2
- https://www.vultr.com/pricing/ (notes region-specific dashboard pricing and paid add-ons)
