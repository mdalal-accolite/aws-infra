# Components, independent state, and per-resource pipeline runs

You asked that adding or changing one resource should run the pipeline for that resource only.
This is how that works, and what it costs.

## The problem with one big state file

The earlier version of this repo kept everything in a single Terraform state per environment.
That has a specific consequence: **every run refreshes every resource.** Change the Redis node
type and Terraform still calls the AWS API for your VPC, your EKS cluster, your CloudFront
distribution, all 150 resources, to confirm nothing drifted. The plan correctly shows only Redis
changing — Terraform never touches what has not diverged — but you wait five minutes to find
out, and one bad plan puts everything in blast radius.

## The fix: one state per component

The infrastructure is now 13 components. Each is a directory under `stacks/` with its own
Terraform state file:

| Component | Contains | State key |
| --- | --- | --- |
| `10-network` | VPC, subnets, IGW, NAT, route tables, VPC endpoints, security groups | `stage/10-network.tfstate` |
| `20-edge` | S3 buckets, CloudFront (4 behaviours), OAC, WAF, access-log bucket | `stage/20-edge.tfstate` |
| `30-registry` | ECR repositories + lifecycle policies | `stage/30-registry.tfstate` |
| `32-messaging` | SQS queue, DLQ, SNS alarm topic | `stage/32-messaging.tfstate` |
| `34-identity` | Cognito user pools and clients | `stage/34-identity.tfstate` |
| `36-secrets` | Secrets Manager entries, API GW log group | `stage/36-secrets.tfstate` |
| `38-email` | **SES** domain identity, DKIM, MAIL FROM, config set | `stage/38-email.tfstate` |
| `40-data` | RDS, RDS Proxy, Redis, their alarms | `stage/40-data.tfstate` |
| `50-iam` | App pod role, CI deploy roles | `stage/50-iam.tfstate` |
| `60-eks` | EKS cluster, add-ons, access entries, pod identity | `stage/60-eks.tfstate` |
| `70-tools` | KiwiTCMS EC2 host | `stage/70-tools.tfstate` |
| `80-api` | API Gateway, VPC link | `stage/80-api.tfstate` |
| `90-vpn` | Client VPN (optional) | `stage/90-vpn.tfstate` |

Now: change the Redis node type, and `terraform plan` in `40-data` refreshes RDS and Redis
only — about twenty seconds. Your VPC is not read, not planned, and cannot be modified by that
run even if the code were wrong, because it is not in that state file.

## How components share values

`40-data` needs the VPC's private subnet ids, which `10-network` created. It reads them from
the upstream state file:

```hcl
data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = module.config.state_bucket
    key    = "${var.environment}/10-network.tfstate"
    region = module.config.env.region
  }
}

# used as:
private_subnet_ids = data.terraform_remote_state.network.outputs.private_subnet_ids
```

This is read-only. `40-data` can see network's outputs and cannot change them.

The number prefixes encode dependency order. A component only ever reads from a
lower-numbered one, which is why alphabetical sorting gives you a valid apply order for free.

```
10-network ──┬──> 40-data ──┐
             ├──> 60-eks    │
             ├──> 70-tools  │
             └──> 90-vpn    │
                            │
20-edge ────────┐           │
30-registry ────┤           │
32-messaging ───┼──> 50-iam ─┴──> 60-eks
34-identity ────┤
38-email ───────┘

34-identity ──> 36-secrets ──> 80-api
32-messaging ──> 38-email
```

## Environment settings live in one file

Splitting into 13 directories could have meant 13 copies of every setting. It does not. Each
component calls the shared `config/` module:

```hcl
module "config" {
  source      = "../../config"
  environment = var.environment
}
```

`config/main.tf` holds one block per environment with every value in it. **To change something
for stage, you edit `config/main.tf` — never a stack directory.** That file is also the reason
there is no `live/stage/` and `live/prod/` any more: the same 13 stacks serve both environments,
with `-var="environment=stage"` choosing which block applies.

The trade-off worth knowing: editing `config/main.tf` affects every component, so CI plans all
13. That is correct — a change to the VPC CIDR really does affect everything. Changes confined
to one component are the common case, and those run alone.

## How CI decides what to run

`.github/workflows/terraform-plan.yml` has a `discover` job that diffs the PR and picks
components:

1. Files under `stacks/40-data/` → plan `40-data`.
2. Files under `modules/data/` → plan every component that uses that module (it greps the stacks
   for `modules/data"`), which is again `40-data`.
3. Files under `config/` or `envs/` → plan all 13, because shared config affects everything.
4. Nothing relevant → no plan jobs at all.

Each selected component becomes a separate matrix job with its own PR comment, so you review
`Plan — stage / 40-data` on its own rather than hunting through a 150-resource diff.

`terraform-apply.yml` does the same on merge to `main`, with `max-parallel: 1` so components
apply in dependency order. If `10-network` and `40-data` both changed, network applies first.

### Worked examples

| You change | CI plans |
| --- | --- |
| `redis_node_type` in `config/main.tf` | all 13 (shared file) |
| A rule in `modules/data/main.tf` | `40-data` |
| `modules/ses/main.tf` | `38-email` |
| `stacks/70-tools/main.tf` | `70-tools` |
| `modules/network/main.tf` | `10-network` |
| `docs/07-NAMING.md` | nothing |

If you want a single-component change without touching shared config, put the value directly in
that stack's `main.tf` instead of in `config/`. That is a reasonable thing to do for anything
only one component cares about.

## Running one component by hand

**Actions → Terraform Component (manual)** takes an environment, a component, and
plan/apply/destroy. Use it for the first build, for prod, and for deliberate re-applies.

Locally:

```bash
cd stacks/40-data
terraform init -input=false \
  -backend-config=../../envs/stage.backend.hcl \
  -backend-config="key=stage/40-data.tfstate"
terraform plan -var="environment=stage"
```

The `key=` is the only thing that differs between components, and the only thing that differs
between environments is the backend file and the `-var`.

## What this costs you

Worth being straight about the downsides:

- **13 state files instead of 1.** All in the same bucket, keyed by environment and component.
- **First build is 13 applies, not 1.** Phase 4.2 gives you a loop. After that it never happens
  again.
- **Apply order matters.** Encoded in the number prefixes and enforced by `max-parallel: 1`.
- **`terraform destroy` is 14 destroys, in reverse order.** Higher numbers first.
- **A component fails if its upstream has never been applied.** The error is
  `Unable to find remote state`, and it means: go apply the lower-numbered component.

## A note on `-target`

Terraform has a `-target=module.x` flag, and it looks like the obvious way to do what you
asked. Don't use it routinely. HashiCorp's own documentation calls it a tool for exceptional
recovery situations, because a targeted apply skips parts of the dependency graph and can write
a state file that no longer matches any plan Terraform would produce on its own. Splitting state
achieves real isolation; `-target` only pretends to.

## Adding a component later

You said you will want more resources added over time. The routine:

1. Write or extend a module under `modules/<name>/`.
2. Create `stacks/NN-<name>/main.tf`, numbered above anything it reads from. Copy the header
   block from an existing stack — the `terraform`, `variable "environment"`, `module "config"`,
   and `provider` blocks are identical in all 13.
3. Add any new settings to both environment blocks in `config/main.tf`.
4. Add the component name to the dropdown in `.github/workflows/terraform-component.yml`.
5. First run via the manual workflow; after that CI picks it up automatically — the `discover`
   job reads `ls stacks/*/`, so there is no list to maintain.
