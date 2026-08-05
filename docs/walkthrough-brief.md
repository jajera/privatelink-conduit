# Walkthrough brief (for a detailed article)

Source material for a long-form article. Prefer published pages over this file.

## Suggested title angles

- Cross-account PrivateLink to a 3-tier private API (NLB → EC2 → RDS)
- Same-region vs cross-region PrivateLink (Sydney + Melbourne)
- Why New Zealand (`ap-southeast-6`) is not in cross-region PrivateLink yet

## Audience

Platform / network engineers who know VPCs and want a minimal PrivateLink lab without
Lattice, TGW, or peering.

## Story arc (map to site pages)

1. Problem → [Overview](index.md)
2. Topology / tiers → [Architecture](architecture.md)
3. Why PrivateLink / design knobs → [How PrivateLink works](privatelink.md)
4. Cross-region knobs + Melbourne → [Cross-Region](cross-region.md)
5. NZ gap → [Lab findings](nz-limitation.md)
6. Deploy / prove / tear down → [Walkthrough](walkthrough.md)
7. Failures → [Troubleshooting](troubleshooting.md)
8. Excluded workarounds → [Alternatives](connectivity-options.md)

## Concepts to explain

- `allowed_principals` vs network reachability
- `acceptance_required = false` (lab vs production)
- `preserve_client_ip = false` vs SG design
- Consumer DNS (`private_dns_enabled = false` + Route 53)
- `SupportedRegions` + `service_region`
- Opt-in Regions (who must opt in)
- Isolation: PrivateLink ≠ VPC routing

## Explicit non-goals

- Production hardening (TLS, multi-AZ app, DRY modules)
- Replacing RDS; NZ stacks; relay workarounds; AI/ML services
