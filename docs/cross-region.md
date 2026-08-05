---
title: Cross-Region PrivateLink
layout: default
nav_order: 4
---

# Cross-Region PrivateLink
{: .no_toc }

The two knobs that make it work, the Melbourne path that proves it, and why
`ap-southeast-6` cannot participate in either direction.
{: .fs-5 .fw-300 }

## On this page
{: .no_toc .text-delta }

- TOC
{:toc}

---

## The short version

{: .finding }
> Cross-Region PrivateLink needs the **provider** to list consumer Regions on the endpoint
> service (`supported_regions`) and the **consumer** to set `service_region` to the host
> Region. Sydney → Melbourne works. `ap-southeast-6` (New Zealand) is rejected in **both**
> directions — it cannot be listed as a consumer Region on a Sydney service, and a service
> hosted in NZ cannot declare supported Regions at all. Same-Region PrivateLink inside NZ
> works; the gap is cross-Region only. Lab notes:
> [Lab findings: New Zealand]({{ site.baseurl }}/nz-limitation/).

## How the feature works

Until late 2024, an interface endpoint could only target an endpoint service in the same
Region. AWS then
[introduced native cross-Region connectivity for PrivateLink](https://aws.amazon.com/blogs/networking-and-content-delivery/introducing-cross-region-connectivity-for-aws-privatelink/),
letting endpoints reach services hosted in other Regions in the same partition, with traffic
staying on the AWS backbone.

It is **provider opt-in, per Region**:

<div class="diagram">
{% include diagrams/cross-region-flow.svg %}
</div>

Two conditions must both hold:

1. The **host Region** must support the feature and must be able to declare supported Regions.
2. The **consumer Region** must be accepted into that list.

Miss either and the consumer can do nothing unilaterally. That is deliberate: a provider
should control where its service is consumable from, since the choice carries data residency
and latency consequences.

## The two knobs

### Provider — `supported_regions`

```terraform
resource "aws_vpc_endpoint_service" "this" {
  acceptance_required        = false
  network_load_balancer_arns = [aws_lb.nlb.arn]
  allowed_principals         = ["arn:aws:iam::${var.sandbox_account_id}:root"]

  supported_regions = var.supported_regions
}
```

```terraform
variable "supported_regions" {
  description = "Regions allowed to create interface endpoints to this service (host Region must be included for cross-Region PrivateLink)"
  type        = list(string)
  default     = ["ap-southeast-2", "ap-southeast-4"]
}
```

The host Region itself must appear in the list, alongside every remote consumer Region.
Omitting the host Region breaks the same-Region consumer.

### Consumer — `service_region`

```terraform
resource "aws_vpc_endpoint" "conduit" {
  vpc_id       = aws_vpc.this.id
  service_name = var.endpoint_service_name

  # Cross-Region PrivateLink: endpoint in Melbourne, service hosted in Sydney.
  service_region = var.endpoint_service_region

  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.endpoint.id]
  private_dns_enabled = false
}
```

Omit `service_region` for a same-Region endpoint, which is exactly the difference between
`terraform/sandbox` and `terraform/sandbox-cross-region`. Everything else — security groups,
DNS, target health — behaves identically.

{: .note }
> These two arguments are the *entire* difference between the same-Region and cross-Region
> consumer roots. That is the useful takeaway: cross-Region PrivateLink is not a different
> architecture, it is two extra arguments, provided your Regions are eligible.

## Opt-in Regions add a prerequisite

Both `ap-southeast-4` (Melbourne) and `ap-southeast-6` (New Zealand) are opt-in Regions, and
this trips people up:

- The **provider** account must be opted into a Region before that Region can be listed in
  `supported_regions`.
- The **consumer** account must be opted in to run resources there.
- Opt-in is necessary but **not sufficient**. Opting into `ap-southeast-6` does not make it
  eligible for cross-Region PrivateLink — the two are unrelated mechanisms.

Check opt-in status before blaming PrivateLink:

```bash
aws account list-regions --profile shared-services \
  --query "Regions[?RegionName=='ap-southeast-4' || RegionName=='ap-southeast-6'].[RegionName,RegionOptStatus]" \
  --output table
```

## The rollout is incremental

Cross-Region support arrived Region by Region, which is why a live API check beats any list
written down here:

| Announcement | Regions added |
|---|---|
| [November 2024 — initial launch](https://aws.amazon.com/about-aws/whats-new/2024/11/aws-privatelink-across-region-connectivity) | N. Virginia, Oregon, Ireland, Singapore, São Paulo, Tokyo, Sydney |
| [December 2024 — 14 more](https://aws.amazon.com/about-aws/whats-new/2024/12/aws-private-link-cross-region-connectivity-additional-regions) | N. California, Ohio, Canada Central, Stockholm, Paris, London, Milan, Frankfurt, Cape Town, Bahrain, Osaka, Hong Kong, Seoul, Mumbai |
| [March 2025 — 6 more](https://aws.amazon.com/about-aws/whats-new/2025/03/aws-privatelink-cross-region-connectivity-6-additional-regions/) | Further Regions |
| [November 2025](https://aws.amazon.com/blogs/networking-and-content-delivery/aws-privatelink-extends-cross-region-connectivity-to-aws-services/) | Extended cross-Region access to AWS services, not only customer-owned services |

`ap-southeast-2` has been eligible since launch, so the Sydney provider and Sydney consumer
were never in question. `ap-southeast-6` opened as a Region
[in 2025](https://aws.amazon.com/blogs/aws/now-open-aws-asia-pacific-new-zealand-region/) and
does not appear in any cross-Region announcement to date.

{: .warning }
> Treat that table as history, not current state. AWS adds Regions to this feature regularly
> and this page will go stale. Verify with a live API call before designing around the
> limitation.

## Verify it yourself

The authoritative test is the API, not documentation.

### What does the service currently accept?

```bash
export AWS_PROFILE=shared-services
export AWS_REGION=ap-southeast-2

SERVICE_ID=$(aws ec2 describe-vpc-endpoint-service-configurations \
  --query 'ServiceConfigurations[0].ServiceId' --output text)

aws ec2 describe-vpc-endpoint-service-configurations \
  --service-ids "$SERVICE_ID" \
  --query 'ServiceConfigurations[0].SupportedRegions'
```

### Try to add a Region

The decisive call. Melbourne succeeds once the provider account is opted in; New Zealand does
not:

```bash
# Succeeds
aws ec2 modify-vpc-endpoint-service-configuration \
  --service-id "$SERVICE_ID" --add-supported-regions ap-southeast-4

# Rejected
aws ec2 modify-vpc-endpoint-service-configuration \
  --service-id "$SERVICE_ID" --add-supported-regions ap-southeast-6
```

Exact message wording varies and has changed over time, so match on the fact of rejection
rather than on a specific string.

### The reverse direction also fails

Worth testing explicitly, because "host it in New Zealand instead" is the obvious next idea.
Creating or configuring an endpoint service **in** `ap-southeast-6` with supported Regions was
rejected — the parameter was not available on that Region's API surface. See
[Lab findings]({{ site.baseurl }}/nz-limitation/) for the detail.

### A reusable check

Keep this so re-testing later is one command:

```bash
#!/usr/bin/env bash
# Does the endpoint service in HOST_REGION accept CONSUMER_REGION?
set -euo pipefail

HOST_REGION="${1:-ap-southeast-2}"
CONSUMER_REGION="${2:-ap-southeast-6}"
PROFILE="${AWS_PROFILE:-shared-services}"

SERVICE_ID=$(aws ec2 describe-vpc-endpoint-service-configurations \
  --profile "$PROFILE" --region "$HOST_REGION" \
  --query 'ServiceConfigurations[0].ServiceId' --output text)

if [[ -z "$SERVICE_ID" || "$SERVICE_ID" == "None" ]]; then
  echo "No endpoint service found in ${HOST_REGION}." >&2
  exit 1
fi

echo "Service ${SERVICE_ID} in ${HOST_REGION}"
echo "Attempting to add ${CONSUMER_REGION}..."

if aws ec2 modify-vpc-endpoint-service-configuration \
     --profile "$PROFILE" --region "$HOST_REGION" \
     --service-id "$SERVICE_ID" \
     --add-supported-regions "$CONSUMER_REGION" 2>/tmp/xrpl.err; then
  echo "SUPPORTED — ${CONSUMER_REGION} is now eligible. Copy the Melbourne stack for it."
  # Leave the service as you found it
  aws ec2 modify-vpc-endpoint-service-configuration \
    --profile "$PROFILE" --region "$HOST_REGION" \
    --service-id "$SERVICE_ID" \
    --remove-supported-regions "$CONSUMER_REGION" >/dev/null
else
  echo "STILL UNSUPPORTED:"
  sed 's/^/  /' /tmp/xrpl.err
fi
```

{: .tip }
> The day this prints `SUPPORTED` for `ap-southeast-6`, the Melbourne consumer root is the
> template — copy `terraform/sandbox-cross-region`, change the Region, CIDR, name prefix, and
> record name. No new concepts required.

## Why there is no workaround inside PrivateLink

Several plausible-sounding ideas do not help. Being precise about this saves time.

{: .blocked }
> **Chaining two endpoint services** does not cross a Region. An endpoint service fronts a
> load balancer in its own VPC, and the endpoint ENI lands in the consumer's VPC in the
> consumer's Region. Neither end provides a Region hop.

{: .blocked }
> **Pointing the provider's NLB at a workload in another Region** does not work. IP-type
> target groups only reach addresses inside the load balancer's VPC or networks connected by
> peering, Direct Connect, or VPN. There is no cross-Region targeting.

{: .blocked }
> **Publishing the private DNS name in the other Region** achieves nothing. DNS resolution is
> not connectivity; an alias to an out-of-Region resource yields an address with no path.

{: .blocked }
> **VPC Lattice as a substitute** does not route around it. Service networks are regional, and
> the documented cross-Region Lattice patterns are built on PrivateLink and resource gateways
> underneath, inheriting the same gap. AWS's own
> [guidance on external connectivity to Lattice](https://docs.aws.amazon.com/solutions/external-connectivity-to-amazon-vpc-lattice/)
> notes that applications outside the Region need a proxy you build and operate.

Because the constraint lives in the control plane rather than the data plane, any answer has
to come from outside PrivateLink — which is why this repo documents the gap and uses Melbourne
instead of shipping a workaround. See
[Alternatives and limits]({{ site.baseurl }}/connectivity-options/) for what those
workarounds would involve and why they are excluded here.
