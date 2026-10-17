# Cloudflare DNS setup — registrar delegation still pending

## Completed and independently read back
- Added `kickbac.vodka` to Nicholas's existing Cloudflare account as a full zone.
- Verified plan **Free Website**, price **$0**; no domain transfer or paid subscription.
- Created `A api.kickbac.vodka -> 144.202.38.243`, TTL **300 seconds**, **DNS-only** (`proxied=false`).
- Reviewed Cloudflare's scan and imported the existing parking entries without changing their targets: apex A records `207.207.210.107` and `207.207.210.229`, plus `*.kickbac.vodka` and `www.kickbac.vodka` CNAMEs to `pixie.porkbun.com`. Final API readback enumerated five records and its pagination metadata agreed.
- Queried BOTH assigned authoritative nameservers directly with nslookup; both returned `144.202.38.243` for the API name.
- Public apex DS lookup had no records; Cloudflare DNSSEC is disabled. No DNSSEC changes were made. If enabling later, coordinate Cloudflare signing and registrar DS only after delegation is active.

This preserves the records observed by the public checks/Cloudflare scan; a quick scan is not a guarantee of discovering every possible custom record. No mail records were observed in the public apex MX/TXT checks. If separate custom services exist, compare their required records before switching nameservers.

## Required registrar action

Cloudflare assigned exactly:

```text
aaden.ns.cloudflare.com
ali.ns.cloudflare.com
```

Public delegation STILL points to Porkbun, and Cloudflare zone status is **pending**. The DNS record is staged and works when querying Cloudflare's nameservers directly, but normal public resolvers are not yet using it.

At [Porkbun Domain Management](https://porkbun.com/):
1. Find `kickbac.vodka` and open **Details**.
2. Under **Nameservers**, click the edit icon.
3. Replace the old Porkbun entries with ONLY the two Cloudflare names above, one per line.
4. Save Nameservers and confirm/Submit if prompted.
5. Reply `nameservers updated`.

Do not add these as ordinary NS records in the Cloudflare zone; they must replace the domain's nameservers at its REGISTRAR. The registrar remains Porkbun. The connector can manage Cloudflare but cannot change a Porkbun registration; local browser automation could not access the locked Chrome profile, and no browser was closed.

After the change, verify the public NS delegation, Cloudflare Active status, public API A resolution and then actual trusted HTTPS. Nameserver propagation can take time; API creation or a direct nameserver query is not proof of global delegation. Do not claim migration complete until public/readback checks pass.

## Application behavior and pending deployment

**NON-BREAKING iOS impact:** API origin remains `https://api.kickbac.vodka`, Auth0 audience remains `https://kickbac-api`, no endpoints/JSON/states changed. No Cloudflare Access login, browser challenge, API cache rule or proxy behavior was added. DNS-only is intentional while setting up/verifying origin HTTPS. Consider Cloudflare proxy plus Full (strict) only after a valid origin certificate is confirmed; never use Flexible TLS to hide a missing origin certificate.

User reports VM `144.202.38.243` at approximately **$28/month**, SSH key selected, **no Vultr firewall attached**. Exact host OS/plan, SSH authentication and origin configuration have not been independently inspected. TCP22 was reachable; TCP80/443 timed out during preflight. No app/server deployment or HTTPS certificate was created. Attach/review the host/cloud firewall before exposing the API; keep8000/database ports private.

Auth0 callback/logout URLs are reported saved. A fresh public prompt=none authorization request now returns302 `login_required`, not Callback URL mismatch, to the URI-equivalent app callback. The redirect lowercases the case-insensitive scheme but preserves `/ios/com.liam.KickBAC/callback`; the supplied identifier remains exactly `com.liam.KickBAC`. This is a public configuration check, not successful user login or token issuance. Logout behavior is not independently tested.

Internal verifiable resource handles and readback snapshot are preserved in the workspace `.project/CLOUDFLARE_DNS.json`, not in credentials/chat.

## References
- https://developers.cloudflare.com/dns/zone-setups/full-setup/setup/
- https://developers.cloudflare.com/dns/manage-dns-records/how-to/create-dns-records/
- https://kb.porkbun.com/article/22-how-to-change-your-nameservers
