---
title: Deploy and destroy
layout: default
nav_order: 6
---

# Deploy and destroy
{: .no_toc }

Build the provider and both consumers, prove the private paths work, prove the direct
paths do not, then tear it all down. Topology context:
[Architecture]({{ site.baseurl }}/architecture/). File map:
[Terraform reference]({{ site.baseurl }}/reference/).
{: .fs-5 .fw-300 }

## On this page
{: .no_toc .text-delta }

- TOC
{:toc}

---

{: .cost }
> This creates billable resources — RDS `db.t4g.micro`, a Network Load Balancer, nine SSM
> interface endpoints across three stacks, two conduit interface endpoints, and three EC2
> instances. Interface endpoints and the NLB bill hourly whether or not traffic flows.
> [Destroy](#destroy) when finished, consumers before the provider.

You can deploy the provider plus **either** consumer independently. The Melbourne path is
optional if you only want the same-Region proof.

## Prerequisites

| Requirement | Check |
|---|---|
| Terraform >= 1.5 | `terraform version` |
| AWS provider ~> 5.0 | resolved by `terraform init` |
| AWS CLI v2 | `aws --version` |
| Profile `shared-services` | `aws sts get-caller-identity --profile shared-services` |
| Profile `sandbox` | `aws sts get-caller-identity --profile sandbox` |
| Session Manager plugin | `session-manager-plugin --version` |

The two profiles must point at **different** accounts. A single account cannot demonstrate a
cross-account boundary.

```bash
aws sts get-caller-identity --profile shared-services --query Account --output text
aws sts get-caller-identity --profile sandbox --query Account --output text
```

### Melbourne only: Region opt-in

`ap-southeast-4` is an opt-in Region, and **both** accounts need it. The provider account must
be opted in before Melbourne can be listed in the service's supported Regions.

```bash
for p in shared-services sandbox; do
  echo "── ${p} ──"
  aws account list-regions --profile "$p" \
    --query "Regions[?RegionName=='ap-southeast-4'].[RegionName,RegionOptStatus]" \
    --output text
done
```

Both should report `ENABLED`. If not, enable and wait for it to finish before applying:

```bash
aws account enable-region --region-name ap-southeast-4 --profile shared-services
```

{: .warning }
> Applying the provider stack with `ap-southeast-4` in `supported_regions` before the provider
> account is opted in will fail. Opt in first.

## Deploy

### Step 1 — Shared variables

```bash
export AWS_REGION=ap-southeast-2

SANDBOX_ACCOUNT_ID=$(AWS_PROFILE=sandbox aws sts get-caller-identity \
  --query Account --output text)

echo "Sandbox account: ${SANDBOX_ACCOUNT_ID}"
```

The provider needs the consumer's account ID for `allowed_principals`. This is the only piece
of information that must flow provider-ward.

### Step 2 — Provider stack (Sydney)

Required for both consumer paths.

```bash
AWS_PROFILE=shared-services terraform -chdir=terraform/shared-services init

AWS_PROFILE=shared-services terraform -chdir=terraform/shared-services apply \
  -var="sandbox_account_id=${SANDBOX_ACCOUNT_ID}"
```

Expect 10 to 15 minutes, almost entirely waiting on RDS. The app instance depends on the
database, so it boots last and seeds configuration on first start.

Build order:

1. VPC, subnets, private route table
2. S3 gateway endpoint and three SSM interface endpoints
3. RDS subnet group, security group, PostgreSQL instance
4. NLB, target group, listener
5. App EC2, seeding the database via user data
6. VPC endpoint service, scoped to the sandbox account, with `supported_regions`

Default `supported_regions` is `["ap-southeast-2", "ap-southeast-4"]` — the host Region plus
Melbourne. To skip the Melbourne path entirely:

```bash
AWS_PROFILE=shared-services terraform -chdir=terraform/shared-services apply \
  -var="sandbox_account_id=${SANDBOX_ACCOUNT_ID}" \
  -var='supported_regions=["ap-southeast-2"]'
```

### Step 3 — Capture provider outputs

```bash
ENDPOINT_SERVICE_NAME=$(AWS_PROFILE=shared-services \
  terraform -chdir=terraform/shared-services output -raw endpoint_service_name)

ENDPOINT_SERVICE_REGION=$(AWS_PROFILE=shared-services \
  terraform -chdir=terraform/shared-services output -raw endpoint_service_region)

echo "${ENDPOINT_SERVICE_NAME} in ${ENDPOINT_SERVICE_REGION}"
# com.amazonaws.vpce.ap-southeast-2.vpce-svc-0123456789abcdef0 in ap-southeast-2
```

Confirm the Regions the service will accept:

```bash
AWS_PROFILE=shared-services terraform -chdir=terraform/shared-services \
  output supported_regions
```

The service name is not a secret — access is enforced by `allowed_principals`, not obscurity.

### Step 4a — Same-Region consumer (Sydney)

```bash
AWS_PROFILE=sandbox terraform -chdir=terraform/sandbox init

AWS_PROFILE=sandbox terraform -chdir=terraform/sandbox apply \
  -var="endpoint_service_name=${ENDPOINT_SERVICE_NAME}"
```

Two to three minutes. No `service_region` — this is the same-Region path.

### Step 4b — Cross-Region consumer (Melbourne)

```bash
AWS_PROFILE=sandbox terraform -chdir=terraform/sandbox-cross-region init

AWS_PROFILE=sandbox terraform -chdir=terraform/sandbox-cross-region apply \
  -var="endpoint_service_name=${ENDPOINT_SERVICE_NAME}" \
  -var="endpoint_service_region=${ENDPOINT_SERVICE_REGION}"
```

The `endpoint_service_region` variable becomes `service_region` on the endpoint, which is what
makes this cross-Region.

### Step 5 — Wait for readiness

Two things must settle, and they cause most false failures.

**The app target must be healthy:**

```bash
TG_ARN=$(AWS_PROFILE=shared-services aws elbv2 describe-target-groups \
  --query "TargetGroups[?contains(TargetGroupName, 'app-tg')].TargetGroupArn" \
  --output text)

AWS_PROFILE=shared-services aws elbv2 describe-target-health \
  --target-group-arn "$TG_ARN" \
  --query 'TargetHealthDescriptions[].TargetHealth.State' --output text
```

Wait for `healthy`. With a 30-second interval and a healthy threshold of 2, that is at least a
minute after the app finishes booting.

**Each test instance must be SSM-registered:**

```bash
TEST_ID=$(AWS_PROFILE=sandbox \
  terraform -chdir=terraform/sandbox output -raw test_ec2_instance_id)

AWS_PROFILE=sandbox aws ssm describe-instance-information \
  --region ap-southeast-2 \
  --filters "Key=InstanceIds,Values=${TEST_ID}" \
  --query 'InstanceInformationList[].PingStatus' --output text
```

Wait for `Online`. Repeat with `--region ap-southeast-4` and the Melbourne instance ID. If
either stays empty past five minutes, see
[Troubleshooting]({{ site.baseurl }}/troubleshooting/#the-test-instance-never-appears-in-ssm).

## Prove it

{: .note }
> `aws ssm send-command` returns immediately with a command ID. Retrieve output with
> `get-command-invocation`, and note that **the `--region` must match the instance's Region**.

### Same-Region success path

```bash
TEST_ID=$(AWS_PROFILE=sandbox \
  terraform -chdir=terraform/sandbox output -raw test_ec2_instance_id)

CMD_ID=$(AWS_PROFILE=sandbox aws ssm send-command \
  --region ap-southeast-2 \
  --instance-ids "$TEST_ID" \
  --document-name AWS-RunShellScript \
  --parameters 'commands=["curl -sS --max-time 10 http://config.conduit.internal/v1/config"]' \
  --query 'Command.CommandId' --output text)

sleep 5

AWS_PROFILE=sandbox aws ssm get-command-invocation \
  --region ap-southeast-2 \
  --command-id "$CMD_ID" --instance-id "$TEST_ID" \
  --query 'StandardOutputContent' --output text
```

Expected shape:

```json
{"configs": {"app.greeting": "...", "...": "..."}, "source": "rds"}
```

### Cross-Region success path

Same payload, reached from Melbourne through Sydney:

```bash
TEST_XR=$(AWS_PROFILE=sandbox \
  terraform -chdir=terraform/sandbox-cross-region output -raw test_ec2_instance_id)

CMD_ID=$(AWS_PROFILE=sandbox aws ssm send-command \
  --region ap-southeast-4 \
  --instance-ids "$TEST_XR" \
  --document-name AWS-RunShellScript \
  --parameters 'commands=["curl -sS --max-time 10 http://config-xr.conduit.internal/v1/config"]' \
  --query 'Command.CommandId' --output text)

sleep 5

AWS_PROFILE=sandbox aws ssm get-command-invocation \
  --region ap-southeast-4 \
  --command-id "$CMD_ID" --instance-id "$TEST_XR" \
  --query 'StandardOutputContent' --output text
```

{: .finding }
> `"source": "rds"` is the meaningful part. It confirms the response came from the data tier in
> Sydney rather than being served statically. Getting it from `config-xr.conduit.internal`
> proves the request crossed a Region boundary over PrivateLink, since the Melbourne VPC has no
> other path to Sydney.

### Isolation proof

Now confirm there is no other path.

```bash
APP_PRIVATE_IP=$(AWS_PROFILE=shared-services \
  terraform -chdir=terraform/shared-services output -raw app_private_ip)

CMD_ID=$(AWS_PROFILE=sandbox aws ssm send-command \
  --region ap-southeast-2 \
  --instance-ids "$TEST_ID" \
  --document-name AWS-RunShellScript \
  --parameters "commands=[\"curl -sS --max-time 5 http://${APP_PRIVATE_IP}/health || echo TIMED_OUT_AS_EXPECTED\"]" \
  --query 'Command.CommandId' --output text)

sleep 8

AWS_PROFILE=sandbox aws ssm get-command-invocation \
  --region ap-southeast-2 \
  --command-id "$CMD_ID" --instance-id "$TEST_ID" \
  --query 'StandardOutputContent' --output text
```

Expect `TIMED_OUT_AS_EXPECTED`. The request hangs until timeout rather than being refused —
the signature of a **missing route**, not a closed port. Neither consumer VPC has a route
toward `10.50.0.0/16`.

The database behaves the same way:

```bash
RDS_ENDPOINT=$(AWS_PROFILE=shared-services \
  terraform -chdir=terraform/shared-services output -raw rds_endpoint)

# From a test host: nc -vz "$RDS_ENDPOINT" 5432   →  timeout
```

### Interactive exploration

```bash
AWS_PROFILE=sandbox aws ssm start-session --region ap-southeast-2 --target "$TEST_ID"
```

Inside the session:

```bash
# Resolves to an address in the consumer's own CIDR
dig +short config.conduit.internal        # 10.51.x.x from Sydney
# dig +short config-xr.conduit.internal   # 10.61.x.x from Melbourne

curl -sS http://config.conduit.internal/v1/config | head -c 500
curl -sS --max-time 5 http://10.50.1.20/health    # substitute real IP; times out
```

{: .tip }
> `dig` is the most instructive command here. The name resolves inside the **consumer's** CIDR,
> not the provider's. That is the clearest demonstration of what PrivateLink does — the service
> appears as a local network interface and no provider addressing is exposed.

## Destroy

{: .warning }
> Destroy **consumers before the provider**. Interface endpoints depend on the provider's
> endpoint service; removing the provider first leaves orphaned endpoints and the provider
> destroy can fail on a service that still has active connections.

### Step 1 — Consumers

```bash
AWS_PROFILE=sandbox terraform -chdir=terraform/sandbox destroy \
  -var="endpoint_service_name=${ENDPOINT_SERVICE_NAME}" \
  -auto-approve

AWS_PROFILE=sandbox terraform -chdir=terraform/sandbox-cross-region destroy \
  -var="endpoint_service_name=${ENDPOINT_SERVICE_NAME}" \
  -var="endpoint_service_region=${ENDPOINT_SERVICE_REGION}" \
  -auto-approve
```

Skip the second command if you never deployed the Melbourne path.

### Step 2 — Provider

```bash
AWS_PROFILE=shared-services terraform -chdir=terraform/shared-services destroy \
  -var="sandbox_account_id=${SANDBOX_ACCOUNT_ID}" \
  -auto-approve
```

RDS is the slow part. The instance sets `skip_final_snapshot = true` and
`deletion_protection = false`, so it deletes without prompting — appropriate for a lab, never
for production.

{: .note }
> Terraform needs variable values to build a destroy plan even though it is removing resources.
> If your shell has expired, re-derive `SANDBOX_ACCOUNT_ID`, `ENDPOINT_SERVICE_NAME`, and
> `ENDPOINT_SERVICE_REGION` first — or see
> [Troubleshooting]({{ site.baseurl }}/troubleshooting/#destroy-fails) if the provider
> state is already gone.

### Step 3 — Verify nothing is left billing

Interface endpoints are the easiest thing to leave running by accident, and they exist in three
Regions' worth of VPCs:

```bash
for r in ap-southeast-2 ap-southeast-4; do
  for p in sandbox shared-services; do
    echo "── ${p} · ${r} ──"
    aws ec2 describe-vpc-endpoints --profile "$p" --region "$r" \
      --query 'VpcEndpoints[].{Id:VpcEndpointId,Service:ServiceName,State:State}' \
      --output table
  done
done
```

Then confirm the load balancer and database are gone:

```bash
AWS_PROFILE=shared-services aws elbv2 describe-load-balancers \
  --query 'LoadBalancers[].LoadBalancerName' --output text

AWS_PROFILE=shared-services aws rds describe-db-instances \
  --query 'DBInstances[].DBInstanceIdentifier' --output text
```

Both should return nothing related to this lab.

{: .tip }
> If a destroy fails partway, re-run it. Terraform is idempotent here and a second pass usually
> clears dependency-ordering hiccups.
