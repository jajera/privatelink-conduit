---
title: Alternatives and limits
layout: default
nav_order: 8
---

# Alternatives and limits
{: .no_toc }

What is genuinely impossible on AWS today, and the workarounds this repo deliberately
does not implement.
{: .fs-5 .fw-300 }

## On this page
{: .no_toc .text-delta }

- TOC
{:toc}

---

{: .warning }
> **None of the workarounds on this page are implemented in this repository.** The lab's
> position is that `ap-southeast-6` is documented as unsupported and Melbourne is used as the
> working cross-Region reference. This page exists so readers understand what the options
> *would* be and why they were excluded — not as a build guide.

## Not actually possible on AWS today

This is the more useful half of the page. Each of these looks plausible and is commonly
proposed.

{: .blocked }
> **Cross-Region PrivateLink involving `ap-southeast-6`.** Rejected in both directions: as a
> consumer Region on a Sydney service, and as a host Region declaring supported Regions. See
> [Cross-Region PrivateLink]({{ site.baseurl }}/cross-region/) and
> [Lab findings]({{ site.baseurl }}/nz-limitation/).

{: .blocked }
> **Direct Connect gateway as VPC-to-VPC transit.** The most common wrong answer, because a
> Direct Connect gateway *can* associate virtual private gateways across Regions and accounts,
> which makes it look like a free cross-Region fabric. It is not. AWS documents that
> [a Direct Connect gateway does not allow associations on the same gateway to send traffic to each other](https://docs.aws.amazon.com/directconnect/latest/UserGuide/direct-connect-gateways-intro.html),
> and the multi-VPC networking whitepaper states it is north/south only. Two virtual private
> gateways on one Direct Connect gateway cannot communicate.

{: .blocked }
> **Site-to-Site VPN directly between two virtual private gateways.** There is no
> managed-endpoint-to-managed-endpoint VPN. One end must be a customer gateway you operate.

{: .blocked }
> **NLB or ALB with IP targets pointing at another Region's private IPs.** IP-type targets must
> be reachable from the load balancer's VPC — locally, or over peering, Direct Connect, or VPN.
> There is no cross-Region targeting, so you cannot skip the network hop by adding targets.

{: .blocked }
> **AWS Global Accelerator as a private path.** An internet-facing front door on edge anycast
> addresses. It provides no private ENI in the consumer VPC and is not private VPC-to-VPC
> connectivity.

{: .blocked }
> **Route 53 alone.** Pointing a private name at an out-of-Region address creates no path. The
> lab's DNS only works because each endpoint ENI is local to its own consumer VPC.

{: .blocked }
> **VPC Lattice as a cross-Region shortcut.** Service networks are regional, and the published
> cross-Region Lattice patterns sit on PrivateLink and resource gateways underneath, inheriting
> the same gap.

## Workarounds excluded from this repo

If you genuinely had a workload pinned to a Region that cross-Region PrivateLink does not
support, and the consumer could not move, these are the realistic options. They are listed for
completeness and ranked by how well they preserve a PrivateLink-like least-privilege posture.

### The shape all of them share

Every option needs *some* cross-Region data path. No AWS feature lets a VPC in one Region reach
an ineligible Region's workload without one. The useful move is to notice that the
least-privilege requirement applies to the **account** boundary, not the Region boundary — so
you keep PrivateLink at the account boundary and solve the Region hop inside the provider's own
account, between two VPCs it already owns:

<div class="diagram">
{% include diagrams/landing-workaround.svg %}
</div>

The consumer stack is unchanged, the consumer still gets one port on one ENI, and the Region hop
becomes an implementation detail the consumer cannot see.

### Ranked

| Rank | Option | Runs on | Operational load | Main objection |
|---|---|---|---|---|
| 1 | Cross-Region VPC peering between the two **provider** VPCs | AWS backbone, encrypted | None | Peering is excluded by this repo's design rules, though intra-account peering to a data-free landing VPC is a materially different risk decision from cross-account peering |
| 2 | Self-managed WireGuard or strongSwan tunnel | Public internet, encrypted | High — patching, HA, MTU, keys | You own an availability-critical component |
| 3 | Site-to-Site VPN with an EC2 customer gateway | Public internet, encrypted | Medium — one appliance, AWS runs the other end | Still a self-managed appliance |
| 4 | AWS Cloud WAN | AWS backbone | Low | [Available in New Zealand since November 2025](https://aws.amazon.com/about-aws/whats-new/2025/11/aws-cloud-wan-thailand-taipei-new-zealand/), but it is Transit Gateway-class routing with per-Region edge charges — heavier than the Transit Gateway this repo already rejects |
| 5 | Reverse-initiated tunnel, far Region dialling out | Public internet | High, bespoke | Best attack surface of any option, zero inbound exposure, but the dial-out agent is stateful |
| 6 | Application-layer relay with mTLS over the internet | Public internet | Medium | Requires public ingress in the far Region, which is usually the exact thing being avoided |

Latency is rarely the deciding factor. Sydney to Auckland is roughly 25 to 30 ms round trip, so
one proxy hop is immaterial for an API like this one.

## A question worth asking first

Does the workload need `ap-southeast-6` specifically, or does it need to be **in New Zealand**?

The [Auckland Local Zone is `ap-southeast-2-akl-1a`, parented to Sydney](https://aws.amazon.com/about-aws/global-infrastructure/localzones/locations/).
If the driver is New Zealand data locality rather than that particular Region code, running the
workload in the Local Zone keeps everything within `ap-southeast-2`, and the plain same-Region
PrivateLink pattern in `terraform/sandbox` works unchanged with no workaround at all.

Local Zones carry a reduced service set — no RDS there, for one — so it will not fit every
workload. But it dissolves the problem instead of routing around it, which makes it worth
settling before building anything.

{: .tip }
> Establish whether the constraint is "New Zealand" or "`ap-southeast-6`" before designing. A
> yes to the Local Zone question removes everything above it.

## The position this repo takes

1. Prove cross-account PrivateLink same-Region: Sydney to Sydney.
2. Prove cross-Region PrivateLink: Sydney provider to Melbourne consumer.
3. Document the New Zealand gap with reproducible API evidence.
4. Ship no workaround. When AWS makes `ap-southeast-6` eligible, copy
   `terraform/sandbox-cross-region` and change four values.
