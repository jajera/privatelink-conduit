---
title: Troubleshooting
layout: default
nav_order: 7
---

# Troubleshooting
{: .no_toc }

The failures you are most likely to hit, ordered roughly by how often they happen.
{: .fs-5 .fw-300 }

## On this page
{: .no_toc .text-delta }

- TOC
{:toc}

---

## Debug in this order

PrivateLink failures are layered, and checking out of order wastes time. Work up the
stack:

<div class="diagram">
{% include diagrams/debug-order.svg %}
</div>

## The curl times out but DNS resolves

The most common failure, and it has three distinct causes that look identical from the
client.

### Cause 1 — the target group is unhealthy

Check this first, always. The endpoint can be `available`, DNS can resolve, TCP can
connect, and requests still fail if there is no healthy target behind the NLB.

```bash
TG_ARN=$(AWS_PROFILE=shared-services aws elbv2 describe-target-groups \
  --query "TargetGroups[?contains(TargetGroupName, 'app-tg')].TargetGroupArn" \
  --output text)

AWS_PROFILE=shared-services aws elbv2 describe-target-health \
  --target-group-arn "$TG_ARN" \
  --query 'TargetHealthDescriptions[].{State:TargetHealth.State,Reason:TargetHealth.Reason,Desc:TargetHealth.Description}' \
  --output table
```

If the state is `unhealthy`, connect to the app instance and check the service directly:

```bash
APP_ID=$(AWS_PROFILE=shared-services aws ec2 describe-instances \
  --filters "Name=tag:Tier,Values=application" "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].InstanceId' --output text)

AWS_PROFILE=shared-services aws ssm start-session --target "$APP_ID"
```

Inside the session:

```bash
curl -sS localhost/health          # is the app even up?
sudo cat /var/log/cloud-init-output.log | tail -50   # did user data succeed?
```

If user data failed, the usual reason is the S3 gateway endpoint not being ready when
`dnf` ran. The stack declares `depends_on` for this, but a re-apply of just the instance
fixes it:

```bash
AWS_PROFILE=shared-services terraform -chdir=terraform/shared-services apply \
  -var="sandbox_account_id=${SANDBOX_ACCOUNT_ID}" \
  -replace='aws_instance.app'
```

### Cause 2 — client IP preservation is on

If the target group has `preserve_client_ip = true`, traffic arriving from PrivateLink
carries the **consumer's** endpoint ENI address as its source — an address from
`10.51.0.0/16`. The provider's app security group knows nothing about that range, so
packets are dropped silently.

The symptom is distinctive: health checks pass (they originate from inside the provider
VPC) but requests through the endpoint time out.

```terraform
resource "aws_lb_target_group" "app" {
  preserve_client_ip = false   # required for this pattern
}
```

See [Architecture]({{ site.baseurl }}/architecture/#client-ip-preservation-is-disabled) for the reasoning.

### Cause 3 — endpoint security group has no ingress

The endpoint ENI needs an ingress rule permitting the client. In this demo that is port 80
from the sandbox VPC CIDR:

```bash
AWS_PROFILE=sandbox aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=*vpce*" \
  --query 'SecurityGroups[].IpPermissions' --output json
```

A missing or wrong-port rule causes a connection timeout that is easy to misattribute to
the provider side.

## The test instance never appears in SSM

Session Manager needs all three interface endpoints — `ssm`, `ssmmessages`, and
`ec2messages`. Missing any one of them means the agent cannot register.

```bash
AWS_PROFILE=sandbox aws ec2 describe-vpc-endpoints \
  --query 'VpcEndpoints[].{Service:ServiceName,State:State,DNS:PrivateDnsEnabled}' \
  --output table
```

All three should be `available` with private DNS enabled. Then verify the instance profile
carries `AmazonSSMManagedInstanceCore`:

```bash
AWS_PROFILE=sandbox aws ec2 describe-instances \
  --instance-ids "$TEST_EC2_INSTANCE_ID" \
  --query 'Reservations[].Instances[].IamInstanceProfile.Arn' --output text
```

Registration typically takes two to four minutes after boot. If nothing appears after
five, terminate and let Terraform recreate:

```bash
AWS_PROFILE=sandbox terraform -chdir=terraform/sandbox apply \
  -var="endpoint_service_name=${ENDPOINT_SERVICE_NAME}" \
  -replace='aws_instance.test'
```

## The endpoint is stuck in pendingAcceptance

```bash
AWS_PROFILE=sandbox aws ec2 describe-vpc-endpoints \
  --query 'VpcEndpoints[].{Id:VpcEndpointId,State:State}' --output table
```

This demo sets `acceptance_required = false`, so it should not happen. If you changed that
to `true`, the provider must approve each connection:

```bash
AWS_PROFILE=shared-services aws ec2 accept-vpc-endpoint-connections \
  --service-id "$SERVICE_ID" \
  --vpc-endpoint-ids "$ENDPOINT_ID"
```

## Endpoint creation is rejected outright

If `terraform apply` on a consumer stack fails at `aws_vpc_endpoint.conduit`, the cause is
usually one of:

| Symptom | Cause |
|---|---|
| Not permitted to create an endpoint for this service | `allowed_principals` does not include the sandbox account. Confirm `sandbox_account_id` was correct. |
| Service not found | Wrong `endpoint_service_name`, or you are querying the wrong Region. |
| Consumer Region not permitted | The consumer Region is not in the service's `supported_regions`. |
| `service_region` rejected | The host Region cannot serve cross-Region endpoints. See [Cross-Region PrivateLink]({{ site.baseurl }}/cross-region/). |

Verify who is allowed:

```bash
AWS_PROFILE=shared-services aws ec2 describe-vpc-endpoint-service-permissions \
  --service-id "$SERVICE_ID" \
  --query 'AllowedPrincipals[].Principal' --output text
```

And which Regions are accepted:

```bash
AWS_PROFILE=shared-services aws ec2 describe-vpc-endpoint-service-configurations \
  --region ap-southeast-2 --service-ids "$SERVICE_ID" \
  --query 'ServiceConfigurations[0].SupportedRegions'
```

## Melbourne: the provider apply fails on supported_regions

`ap-southeast-4` is an opt-in Region and the **provider** account must be opted in before it
can be listed. This fails otherwise, and the error points at the endpoint service rather than
at Region opt-in, which is misleading.

```bash
for p in shared-services sandbox; do
  echo "── ${p} ──"
  aws account list-regions --profile "$p" \
    --query "Regions[?RegionName=='ap-southeast-4'].[RegionName,RegionOptStatus]" \
    --output text
done
```

Both must be `ENABLED`. Enable and wait before retrying:

```bash
aws account enable-region --region-name ap-southeast-4 --profile shared-services
```

To proceed without Melbourne at all:

```bash
AWS_PROFILE=shared-services terraform -chdir=terraform/shared-services apply \
  -var="sandbox_account_id=${SANDBOX_ACCOUNT_ID}" \
  -var='supported_regions=["ap-southeast-2"]'
```

{: .warning }
> Opt-in is necessary but not sufficient. Opting into `ap-southeast-6` does **not** make it
> eligible for cross-Region PrivateLink — the mechanisms are unrelated. See
> [Lab findings]({{ site.baseurl }}/nz-limitation/).

## SSM commands return nothing for the Melbourne host

Almost always a Region mismatch. `send-command`, `get-command-invocation`, and
`describe-instance-information` all need `--region ap-southeast-4` for the cross-Region
consumer. Using the default Sydney Region returns an invalid-instance error or empty output.

```bash
# Correct for the Melbourne test host
AWS_PROFILE=sandbox aws ssm describe-instance-information \
  --region ap-southeast-4 \
  --query 'InstanceInformationList[].{Id:InstanceId,Ping:PingStatus}' --output table
```

## DNS resolves to the wrong thing

```bash
# From the test host
dig +short config.conduit.internal
```

Expect one or more addresses inside the **sandbox** CIDR, `10.51.x.x`. Anything else means
the alias record is wrong.

If it returns nothing, check that the private hosted zone is associated with the sandbox
VPC:

```bash
ZONE_ID=$(AWS_PROFILE=sandbox aws route53 list-hosted-zones-by-name \
  --dns-name conduit.internal \
  --query 'HostedZones[0].Id' --output text)

AWS_PROFILE=sandbox aws route53 get-hosted-zone --id "$ZONE_ID" \
  --query 'VPCs[].VPCId' --output text
```

An unassociated zone resolves for nobody. Also confirm the VPC has both
`enable_dns_support` and `enable_dns_hostnames` set, since private hosted zones require
them.

## Destroy fails

### The endpoint service still has connections

Destroy the consumer stack first. If you destroyed the provider first, delete the orphaned
endpoint manually:

```bash
AWS_PROFILE=sandbox aws ec2 delete-vpc-endpoints \
  --vpc-endpoint-ids "$ENDPOINT_ID"
```

Then re-run the provider destroy.

### Terraform asks for variables during destroy

Terraform needs variable values to build a destroy plan, even though it is removing
resources. Re-derive them:

```bash
SANDBOX_ACCOUNT_ID=$(AWS_PROFILE=sandbox aws sts get-caller-identity \
  --query Account --output text)

ENDPOINT_SERVICE_NAME=$(AWS_PROFILE=shared-services \
  terraform -chdir=terraform/shared-services output -raw endpoint_service_name)
```

If the provider state is already gone and you cannot read the output, pass any
syntactically valid placeholder — the consumer destroy does not use the value for
anything except planning:

```bash
AWS_PROFILE=sandbox terraform -chdir=terraform/sandbox destroy \
  -var="endpoint_service_name=com.amazonaws.vpce.ap-southeast-2.vpce-svc-0" \
  -auto-approve
```

### The VPC will not delete

Almost always a leftover ENI. Find what still holds it:

```bash
AWS_PROFILE=sandbox aws ec2 describe-network-interfaces \
  --filters "Name=vpc-id,Values=${VPC_ID}" \
  --query 'NetworkInterfaces[].{Id:NetworkInterfaceId,Desc:Description,Status:Status}' \
  --output table
```

Endpoint ENIs disappear when their endpoint is deleted. NLB ENIs can take several minutes
after the load balancer goes away — wait, then retry.

## Getting more signal

Enable VPC Flow Logs on both sides when a failure resists diagnosis. On the provider,
flow logs show whether traffic arrives at the app tier at all, which cleanly separates
"PrivateLink is not delivering" from "the app is rejecting".

```bash
# Confirm the endpoint's network interfaces and their addresses
AWS_PROFILE=sandbox aws ec2 describe-vpc-endpoints \
  --vpc-endpoint-ids "$ENDPOINT_ID" \
  --query 'VpcEndpoints[].NetworkInterfaceIds' --output text
```

{: .tip }
> Remember PrivateLink is TCP only. `ping` against the endpoint address fails even when
> everything is working correctly, so never use ICMP as a reachability test here. Use
> `curl`, `nc -vz`, or `openssl s_client`.
