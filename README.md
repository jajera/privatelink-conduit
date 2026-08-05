# privatelink-conduit

Cross-account **AWS PrivateLink** lab: a sandbox consumer reaches a private **3-tier** shared-config API in shared-services over an interface endpoint. There is **no** VPC peering, Transit Gateway, or route to the provider’s app or RDS private IPs.

| Role | AWS CLI profile | What it owns |
|------|-----------------|--------------|
| Provider | `shared-services` | VPC, NLB, app EC2, RDS Postgres, VPC endpoint service |
| Consumer | `sandbox` | VPC, interface endpoint, private DNS, test EC2 (SSM/`curl`) |

## Paths in this repo

| Path | Provider region | Consumer region | Private DNS | Terraform roots |
|------|-----------------|-----------------|-------------|-----------------|
| Same-region | `ap-southeast-2` (Sydney) | `ap-southeast-2` | `config.conduit.internal` | `shared-services` + `sandbox` |
| Cross-region | `ap-southeast-2` (Sydney) | `ap-southeast-4` (Melbourne) | `config-xr.conduit.internal` | `shared-services` + `sandbox-cross-region` |

Both consumers talk to the **same** Sydney provider stack. Cross-region uses native PrivateLink (`supported_regions` on the service, `service_region` on the consumer endpoint).

**Not in this repo:** an `ap-southeast-6` (NZ) stack. Cross-region PrivateLink involving NZ is not supported today — see [docs/nz-limitation.md](docs/nz-limitation.md).

## Docs

📖 **[Published documentation site](https://jajera.github.io/privatelink-conduit/)** — long-form
walkthrough, architecture, PrivateLink mechanics, the NZ limitation, and troubleshooting.

| Doc | Purpose |
|-----|---------|
| [docs/index.md](docs/index.md) | Site overview and reading order |
| [docs/architecture.md](docs/architecture.md) | Topology, tiers, CIDRs, sample API |
| [docs/privatelink.md](docs/privatelink.md) | Mechanics + lab design (DNS, client IP, SGs) |
| [docs/cross-region.md](docs/cross-region.md) | `supported_regions` / `service_region`, Melbourne |
| [docs/nz-limitation.md](docs/nz-limitation.md) | Lab findings for `ap-southeast-6` |
| [docs/walkthrough.md](docs/walkthrough.md) | Deploy, prove (incl. isolation), destroy |
| [docs/troubleshooting.md](docs/troubleshooting.md) | Common failures |
| [docs/connectivity-options.md](docs/connectivity-options.md) | Impossible paths and excluded workarounds |
| [docs/reference.md](docs/reference.md) | Terraform file map |
| [docs/walkthrough-brief.md](docs/walkthrough-brief.md) | Authoring notes (not published) |

The site is built with [just-the-docs](https://just-the-docs.com/) and deploys from
`.github/workflows/docs.yml`.

### Preview docs locally

**Docker (recommended — no Ruby on the host):**

```bash
./scripts/docs-serve.sh
# or: docker compose -f docs/docker-compose.yml up
```

Open [http://127.0.0.1:4000/privatelink-conduit/](http://127.0.0.1:4000/privatelink-conduit/)
(`baseurl` matches GitHub Pages). Use the header moon/sun control to toggle dark mode
(preference saved in `localStorage`).


**Host Ruby / Bundler:**

```bash
cd docs && bundle install && bundle exec jekyll serve --livereload
```

## Layout

```text
terraform/
  shared-services/        # Sydney provider
  sandbox/                # Sydney same-region consumer
  sandbox-cross-region/   # Melbourne cross-region consumer
docs/                     # just-the-docs site (GitHub Pages)
  _config.yml
  Gemfile
  index.md
  architecture.md
  privatelink.md
  cross-region.md
  nz-limitation.md
  walkthrough.md
  troubleshooting.md
  connectivity-options.md
  reference.md
  diagrams/               # README + regen notes for SVG includes
  _includes/diagrams/     # theme-aware SVG figures
  scripts/generate-diagrams.py
  walkthrough-brief.md    # authoring notes, excluded from the build
```

## Prerequisites

- Terraform `>= 1.5`, AWS provider `~> 5.0`
- AWS CLI profiles `shared-services` and `sandbox`
- [Session Manager plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html)
- For Melbourne: both accounts **opted into** `ap-southeast-4` (the provider account must be opted in before `ap-southeast-4` can appear in `SupportedRegions`)

## Deploy

### 1. Provider (Sydney) — required for both paths

```bash
SANDBOX_ACCOUNT_ID=$(AWS_PROFILE=sandbox aws sts get-caller-identity --query Account --output text)

AWS_PROFILE=shared-services terraform -chdir=terraform/shared-services init
AWS_PROFILE=shared-services terraform -chdir=terraform/shared-services apply \
  -var="sandbox_account_id=$SANDBOX_ACCOUNT_ID"

ENDPOINT_SERVICE_NAME=$(AWS_PROFILE=shared-services terraform -chdir=terraform/shared-services output -raw endpoint_service_name)
ENDPOINT_SERVICE_REGION=$(AWS_PROFILE=shared-services terraform -chdir=terraform/shared-services output -raw endpoint_service_region)
```

Default `supported_regions` is `["ap-southeast-2", "ap-southeast-4"]`.

### 2a. Same-region consumer (Sydney)

```bash
AWS_PROFILE=sandbox terraform -chdir=terraform/sandbox init
AWS_PROFILE=sandbox terraform -chdir=terraform/sandbox apply \
  -var="endpoint_service_name=$ENDPOINT_SERVICE_NAME"
```

### 2b. Cross-region consumer (Melbourne)

```bash
AWS_PROFILE=sandbox terraform -chdir=terraform/sandbox-cross-region init
AWS_PROFILE=sandbox terraform -chdir=terraform/sandbox-cross-region apply \
  -var="endpoint_service_name=$ENDPOINT_SERVICE_NAME" \
  -var="endpoint_service_region=$ENDPOINT_SERVICE_REGION"
```

## Prove it

Retrieve SSM command output with `aws ssm get-command-invocation` (or the console) after `send-command`.

```bash
# Same-region — expect JSON with "source": "rds"
TEST_ID=$(AWS_PROFILE=sandbox terraform -chdir=terraform/sandbox output -raw test_ec2_instance_id)
AWS_PROFILE=sandbox aws ssm send-command --region ap-southeast-2 \
  --instance-ids "$TEST_ID" --document-name AWS-RunShellScript \
  --parameters 'commands=["curl -sS --max-time 10 http://config.conduit.internal/v1/config"]'

# Cross-region — same payload via Melbourne endpoint
TEST_XR=$(AWS_PROFILE=sandbox terraform -chdir=terraform/sandbox-cross-region output -raw test_ec2_instance_id)
AWS_PROFILE=sandbox aws ssm send-command --region ap-southeast-4 \
  --instance-ids "$TEST_XR" --document-name AWS-RunShellScript \
  --parameters 'commands=["curl -sS --max-time 10 http://config-xr.conduit.internal/v1/config"]'
```

Isolation check (should time out): from the test host, `curl` the provider `app_private_ip` or `rds_endpoint` from shared-services outputs — the sandbox VPC has no route there.

API surface on the app:

- `GET /health` → `{"status":"ok"}`
- `GET /v1/config` → seeded feature flags / greeting from Postgres

## Destroy

Destroy **consumers before** the provider.

```bash
AWS_PROFILE=sandbox terraform -chdir=terraform/sandbox destroy \
  -var="endpoint_service_name=$ENDPOINT_SERVICE_NAME" -auto-approve

AWS_PROFILE=sandbox terraform -chdir=terraform/sandbox-cross-region destroy \
  -var="endpoint_service_name=$ENDPOINT_SERVICE_NAME" \
  -var="endpoint_service_region=$ENDPOINT_SERVICE_REGION" -auto-approve

AWS_PROFILE=shared-services terraform -chdir=terraform/shared-services destroy \
  -var="sandbox_account_id=$SANDBOX_ACCOUNT_ID" -auto-approve
```

## Cost note

Stacks leave NLB, EC2, RDS, interface endpoints, and related resources running until destroyed. Tear down when finished.
