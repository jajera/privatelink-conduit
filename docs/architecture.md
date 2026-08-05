---
title: Architecture
layout: default
nav_order: 2
---

# Architecture
{: .no_toc }

How the lab is put together: one provider, two consumers, a 3-tier private API, and the
addressing that makes the proofs readable.
{: .fs-5 .fw-300 }

## On this page
{: .no_toc .text-delta }

- TOC
{:toc}

---

## Topology

One Sydney provider serves two sandbox consumers — same-Region and cross-Region — over the
**same** VPC endpoint service. Neither consumer has peering, Transit Gateway, or a route to
`10.50.0.0/16`.

<div class="diagram">
{% include diagrams/topology.svg %}
</div>

| | Provider | Same-Region consumer | Cross-Region consumer |
|---|---|---|---|
| Account / profile | `shared-services` | `sandbox` | `sandbox` |
| Region | `ap-southeast-2` | `ap-southeast-2` | `ap-southeast-4` |
| VPC CIDR | `10.50.0.0/16` | `10.51.0.0/16` | `10.61.0.0/16` |
| Terraform root | `terraform/shared-services` | `terraform/sandbox` | `terraform/sandbox-cross-region` |
| Private DNS | — | `config.conduit.internal` | `config-xr.conduit.internal` |
| Cross-Region knob | `supported_regions` | — | `service_region = ap-southeast-2` |

CIDRs do not need to be unique for PrivateLink (no routes are exchanged). Distinct ranges
here make `dig` output easier to read during proofs.

## Provider tiers

The provider is a conventional 3-tier app so the demo can prove traffic reaches the **data**
tier. Any TCP workload behind an NLB can replace it.

| Tier | Resource | Subnets | Reachable from |
|---|---|---|---|
| Presentation | Internal NLB, TCP 80 | `app` (2 AZs) | Consumers via the endpoint service |
| Application | EC2 `t3.micro`, HTTP 80 | `app` AZ-a | NLB (+ VPC CIDR for health checks) |
| Data | RDS PostgreSQL 16, `db.t4g.micro` | `data` (2 AZs) | App security group on 5432 only |

Everything is private: **no IGW and no NAT** in any of the three VPCs. Package installs and
Session Manager use VPC endpoints only.

<div class="diagram">
{% include diagrams/provider-tiers.svg %}
</div>

Subnet layout:

| Stack | Region | VPC | Subnets |
|---|---|---|---|
| `shared-services` | `ap-southeast-2` | `10.50.0.0/16` | app `.1/.2` · data `.11/.12` |
| `sandbox` | `ap-southeast-2` | `10.51.0.0/16` | private `.1/.2` |
| `sandbox-cross-region` | `ap-southeast-4` | `10.61.0.0/16` | private `.1/.2` |

## Consumer shape

Each consumer VPC has private subnets, SSM/S3 endpoints, a test EC2, an interface endpoint to
the Sydney service, and a **private hosted zone** alias:

| Consumer | Record | Resolves to |
|---|---|---|
| Sydney | `config.conduit.internal` | Local endpoint ENIs in `10.51.0.0/16` |
| Melbourne | `config-xr.conduit.internal` | Local endpoint ENIs in `10.61.0.0/16` |

Two names keep the proofs unambiguous. Why `private_dns_enabled = false` and how DNS options
compare is covered in [How PrivateLink works]({{ site.baseurl }}/privatelink/#dns-for-this-lab).

## Sample API

Userdata installs a small Python HTTP API and seeds Postgres.

| Path | Purpose |
|---|---|
| `GET /health` | NLB health check → `{"status":"ok"}` |
| `GET /v1/config` | Seeded config JSON including `"source": "rds"` |

`"source": "rds"` is how the [walkthrough]({{ site.baseurl }}/walkthrough/#prove-it) shows the
request traversed all three tiers.

## Where the rest lives

| Topic | Page |
|---|---|
| Provider/consumer mechanics, least privilege, lab design choices (client IP, SGs, DNS) | [How PrivateLink works]({{ site.baseurl }}/privatelink/) |
| `supported_regions` / `service_region`, Melbourne path | [Cross-Region PrivateLink]({{ site.baseurl }}/cross-region/) |
| NZ gap observations | [Lab findings: New Zealand]({{ site.baseurl }}/nz-limitation/) |
| Deploy, prove (including isolation), destroy | [Deploy and destroy]({{ site.baseurl }}/walkthrough/) |
| Terraform file map | [Terraform reference]({{ site.baseurl }}/reference/) |
| Failure signatures | [Troubleshooting]({{ site.baseurl }}/troubleshooting/) |
