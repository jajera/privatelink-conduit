---
title: "Lab findings: New Zealand"
layout: default
nav_order: 5
---

# Lab findings: New Zealand
{: .no_toc }

What we observed for `ap-southeast-6` and cross-Region PrivateLink. Mechanism and Melbourne
workaround: [Cross-Region PrivateLink]({{ site.baseurl }}/cross-region/).
{: .fs-5 .fw-300 }

## On this page
{: .no_toc .text-delta }

- TOC
{:toc}

---

## Summary

| Direction | Result |
|---|---|
| Same-Region PrivateLink **in** NZ | Works |
| NZ as consumer in a Sydney service `SupportedRegions` | Rejected |
| NZ as host of a service that declares `SupportedRegions` | Rejected |

This repo uses **Melbourne (`ap-southeast-4`)** as the cross-Region consumer against Sydney.
It does **not** ship NZ Terraform roots.

## Observations

Re-verify against current AWS docs/APIs before publishing dates.

1. **Sydney → allow NZ consumers** — Adding `ap-southeast-6` to `SupportedRegions` on an
   `ap-southeast-2` endpoint service failed. NZ was not in the remote-access set (unlike
   `ap-southeast-4` after opt-in).

2. **NZ-hosted service → remote consumers** — Creating/configuring an endpoint service *in*
   NZ with `SupportedRegions` was rejected (parameter not available on that Region's API
   surface in the lab).

3. **Same-Region NZ** — Provider + consumer both in NZ completed PrivateLink without
   `SupportedRegions` / `service_region`. Removed from the repo to keep focus on the
   cross-Region story.

4. **Opt-in ≠ feature** — Opting into NZ (or Melbourne) does not enable cross-Region
   PrivateLink for NZ. For Melbourne, the **provider** account must be opted into
   `ap-southeast-4` before that Region can appear in `SupportedRegions`.

5. **Roadmap** — No public “what's new” found naming NZ as GA for cross-Region PrivateLink
   as of this lab. Treat as not available until AWS documents it; escalate via TAM with the
   API errors.

Reusable CLI checks live under
[Verify it yourself]({{ site.baseurl }}/cross-region/#verify-it-yourself) on the
cross-Region page.

## What this demo does instead

| Goal | In-repo approach |
|---|---|
| Cross-account PrivateLink | Sydney ↔ Sydney |
| Cross-Region PrivateLink | Sydney ↔ Melbourne |
| Document the NZ gap | This page |

## Out of scope

Not implemented (see [Alternatives and limits]({{ site.baseurl }}/connectivity-options/)):

- Peering or Transit Gateway between Regions/accounts
- Public HTTPS front door
- DIY tunnels / relays

When AWS adds NZ to cross-Region PrivateLink, copy the Melbourne consumer pattern
(`supported_regions` + `service_region`).
