---
title: How PrivateLink works
layout: default
nav_order: 3
---

# How PrivateLink works
{: .no_toc }

Provider and consumer roles, why PrivateLink is least privilege, and the lab design choices
that are easy to get wrong. For Region hops, continue to
[Cross-Region PrivateLink]({{ site.baseurl }}/cross-region/).
{: .fs-5 .fw-300 }

## On this page
{: .no_toc .text-delta }

- TOC
{:toc}

---

## Two roles

PrivateLink is deliberately asymmetric. That asymmetry is the security value.

**The provider** owns a workload and publishes a *VPC endpoint service* fronted by a Network
Load Balancer (or Gateway Load Balancer). It decides which principals may connect and whether
each connection needs manual acceptance.

**The consumer** creates an *interface endpoint* in its own VPC. AWS places an ENI in the
consumer's subnets with an address from the **consumer's** CIDR. Clients connect to that local
address.

<div class="diagram">
{% include diagrams/request-path.svg %}
</div>

## Least privilege

Four properties you lose when you substitute peering or Transit Gateway:

**Unidirectional by construction.** The consumer initiates; the provider receives. The
provider gains no route into the consumer VPC.

**No CIDR coordination.** The endpoint ENI is a consumer address. Overlapping CIDRs between
accounts are irrelevant.

**One service, not a network.** Reachability is limited to the endpoint service and its
listener ports — not the provider VPC as a whole.

**Two policy layers.** Security groups on the consumer endpoint ENI control who may use it;
endpoint policies (where supported) can further constrain API/resource access.

## Compared with routed alternatives

| | PrivateLink | VPC Peering | Transit Gateway |
|---|---|---|---|
| Unit of access | One service | Whole VPC CIDRs | Whole attached networks |
| Direction | Consumer → provider | Bidirectional | Bidirectional |
| Overlapping CIDRs | Fine | Blocks peering | Blocks or needs NAT |
| Cross-Region | Opt-in, Region-dependent | Broadly supported | Inter-Region peering |
| Typical failure mode | Health checks, SGs | Route sprawl | Route sprawl, blast radius |

For a single service shared across accounts, PrivateLink is usually the right default. That
is why losing it for some Regions is painful rather than academic — see
[Cross-Region PrivateLink]({{ site.baseurl }}/cross-region/).

## Components

### Endpoint service (provider)

```terraform
resource "aws_vpc_endpoint_service" "this" {
  acceptance_required        = false
  network_load_balancer_arns = [aws_lb.nlb.arn]
  allowed_principals         = ["arn:aws:iam::${var.sandbox_account_id}:root"]
  supported_regions          = var.supported_regions
}
```

The service name looks like
`com.amazonaws.vpce.ap-southeast-2.vpce-svc-0123456789abcdef0`. It is not a secret —
`allowed_principals` enforces access.

| Control | Meaning |
|---|---|
| `allowed_principals` | *Who* may create an endpoint |
| `supported_regions` | *From which Regions* (cross-Region); see [cross-region]({{ site.baseurl }}/cross-region/) |
| `acceptance_required` | Manual approve each connection (`false` here for lab convenience) |

Also:

- An **NLB** (or GWLB) is required — you cannot publish an instance or ALB directly as an
  interface endpoint service (NLB-in-front-of-ALB is the usual ALB pattern).
- Prefer the narrowest principal. `*` with `acceptance_required = false` opens the service to
  every account in the partition.

### Interface endpoint (consumer)

```terraform
resource "aws_vpc_endpoint" "conduit" {
  vpc_id              = aws_vpc.this.id
  service_name        = var.endpoint_service_name
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.endpoint.id]
  private_dns_enabled = false
  # Cross-Region only:
  # service_region    = "ap-southeast-2"
}
```

One ENI per listed subnet (two AZs → two ENIs). Each ENI bills hourly. `dns_entry` feeds the
consumer's Route 53 alias.

## DNS for this lab

| Approach | When to use | Trade-off |
|---|---|---|
| Endpoint regional DNS name | Quick tests | Ugly; changes if the endpoint is recreated |
| Provider private DNS name | Branded SaaS name | Provider must verify domain ownership |
| **Consumer private hosted zone** (this lab) | Custom internal names | Consumer owns naming; no provider coordination |

This lab uses consumer-owned zones named `conduit.internal`, each associated only with that
consumer VPC:

| Consumer | Record |
|---|---|
| Sydney | `config.conduit.internal` |
| Melbourne | `config-xr.conduit.internal` |

```terraform
resource "aws_vpc_endpoint" "conduit" {
  # ...
  private_dns_enabled = false
}

resource "aws_route53_record" "config" {
  zone_id = aws_route53_zone.conduit.zone_id
  name    = "config.conduit.internal"
  type    = "A"

  alias {
    name                   = aws_vpc_endpoint.conduit.dns_entry[0].dns_name
    zone_id                = aws_vpc_endpoint.conduit.dns_entry[0].hosted_zone_id
    evaluate_target_health = true
  }
}
```

{: .note }
> The alias resolves to ENI addresses **in the consumer VPC**. The name only resolves inside
> VPCs associated with the zone — nothing leaks to public DNS.

## Lab design choices

These are the settings that are easy to get wrong and hard to debug. Symptoms often land in
[Troubleshooting]({{ site.baseurl }}/troubleshooting/).

### Client IP preservation is off

```terraform
resource "aws_lb_target_group" "app" {
  preserve_client_ip = false
  # ...
}
```

With preservation **on**, the app sees the **consumer** endpoint ENI as the source
(`10.51.x.x` / `10.61.x.x`). The provider app SG does not allow those CIDRs, so traffic drops
while NLB health checks (from inside the provider VPC) still pass.

Turning preservation **off** makes the NLB the apparent source, which the app SG already
allows. Trade-off: the app cannot see the real client IP (use PROXY protocol v2 if you need
it).

### Security group chain

<div class="diagram">
{% include diagrams/sg-chain.svg %}
</div>

Each hop is a single port from a named source. The app SG also allows `:80` from the
provider VPC CIDR so NLB health checks succeed (health-check sources are subnet addresses,
not a reusable SG reference in this setup).

### No NAT, no internet gateway

Credibility for a “private path” lab: nothing can quietly fall back to the public internet.

| Endpoint | Why |
|---|---|
| S3 gateway | AL2023 `dnf` (repos on S3); free; route-table attachment |
| `ssm` / `ssmmessages` / `ec2messages` | Session Manager; missing any one → instance never registers |

## Limits worth knowing

- **TCP only.** `ping` against the endpoint proves nothing.
- **Listener ports define reachability.** New ports need a provider listener, not only a
  consumer SG rule.
- **Unhealthy targets fail the path.** DNS and TCP can succeed while HTTP still fails — check
  target health first.
- **Cross-zone vs cost.** Off: ENI in an AZ without healthy targets fails. On: inter-AZ data
  transfer charges.
- **ENIs bill hourly**, plus data processing. SSM endpoints across three stacks plus conduit
  endpoints add up — tear down when finished.
