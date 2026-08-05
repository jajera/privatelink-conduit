---
title: Terraform reference
layout: default
nav_order: 9
---

# Terraform reference
{: .no_toc }

File map for the three roots. Behaviour and topology live in
[Architecture]({{ site.baseurl }}/architecture/); apply order lives in
[Deploy and destroy]({{ site.baseurl }}/walkthrough/).
{: .fs-5 .fw-300 }

## On this page
{: .no_toc .text-delta }

- TOC
{:toc}

---

## Layout

```text
terraform/
  shared-services/        # Sydney provider
  sandbox/                # Sydney same-Region consumer
  sandbox-cross-region/   # Melbourne cross-Region consumer
```

## Provider — `terraform/shared-services`

| File | Contents |
|---|---|
| `vpc.tf` | VPC, app + data subnets (2 AZs), private route table, S3 gateway endpoint, SSM interface endpoints |
| `app.tf` | AMI lookup, app SG, SSM IAM role/profile, app EC2 |
| `data.tf` | DB password, subnet group, DB SG, RDS Postgres |
| `presentation.tf` | NLB, target group (`preserve_client_ip = false`), listener, **VPC endpoint service** |
| `templates/app_userdata.sh.tftpl` | Config API install + Postgres seed |
| `variables.tf` | Region, profile, CIDR, `sandbox_account_id`, `supported_regions` |
| `outputs.tf` | `endpoint_service_name`, `endpoint_service_region`, `supported_regions`, `app_private_ip`, `rds_endpoint` |

Defaults: Region `ap-southeast-2`, CIDR `10.50.0.0/16`,
`supported_regions = ["ap-southeast-2", "ap-southeast-4"]`.

## Consumers

`terraform/sandbox` and `terraform/sandbox-cross-region` are near-identical.

| File | Contents |
|---|---|
| `vpc.tf` | VPC, private subnets (2 AZs), S3 + SSM endpoints |
| `endpoint.tf` | Endpoint SG, **interface endpoint**, private hosted zone, alias A record |
| `test.tf` | Test EC2 + SSM instance profile (no inbound rules) |
| `variables.tf` | Region, CIDR, `endpoint_service_name` (+ `endpoint_service_region` on XR) |
| `outputs.tf` | `test_ec2_instance_id`, `conduit_dns_name`, `endpoint_dns_name` |

### Differences

| | `sandbox` | `sandbox-cross-region` |
|---|---|---|
| Region | `ap-southeast-2` | `ap-southeast-4` |
| CIDR | `10.51.0.0/16` | `10.61.0.0/16` |
| Name prefix | `plc` → `plc-sbx` | `plc-xr` → `plc-xr-sbx` |
| DNS record | `config.conduit.internal` | `config-xr.conduit.internal` |
| `service_region` | unset | `ap-southeast-2` |

## Apply order

1. Provider (`sandbox_account_id`)
2. One or both consumers (`endpoint_service_name`, and `endpoint_service_region` for Melbourne)
3. Destroy consumers before provider

Full commands: [Deploy and destroy]({{ site.baseurl }}/walkthrough/).
