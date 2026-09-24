# Tagging

Tags are how you answer "what is this, who owns it, and can I delete it" six months from now,
and how finance splits the bill between stage and prod.

## Two layers

**Layer 1 — provider default tags.** In `live/<env>/providers.tf`:

```hcl
provider "aws" {
  default_tags {
    tags = {
      Project     = "scribl"
      Environment = "stage"
      ManagedBy   = "terraform"
    }
  }
}
```

These are applied by the AWS provider to every resource that supports tagging, without any
module having to ask. Nothing gets missed.

**Layer 2 — module tags.** `stacks/environment/main.tf` builds a richer set and passes it down:

```hcl
common_tags = merge({
  Project     = var.project        # scribl
  Environment = var.environment    # stage | prod
  ManagedBy   = "terraform"
  Repository  = "ScriblOrg/scribl-infra"
  CostCenter  = var.cost_center
  Owner       = var.owner
}, var.extra_tags)
```

Each module then merges a `Name`, and sometimes a `Tier` or `Purpose`:

```hcl
tags = merge(var.tags, {
  Name = "${var.name_prefix}-private-us-east-1a"
  Tier = "private"
})
```

## What every resource ends up with

| Tag | Example | Purpose |
| --- | --- | --- |
| `Name` | `scribl-stage-vpc` | what shows in the console |
| `Project` | `scribl` | separates this from other work in the account |
| `Environment` | `stage` | **the one that drives cost allocation** |
| `ManagedBy` | `terraform` | warns humans off editing it by hand |
| `Repository` | `ScriblOrg/scribl-infra` | where the code is |
| `CostCenter` | `engineering` | finance's split |
| `Owner` | `platform-team` | who to page |
| `Tier` | `private` / `public` | on subnets |
| `Purpose` | `web-spa`, `user-media`, `terraform-state` | on things whose name is not self-explanatory |

Plus functional tags Kubernetes needs, which are not cosmetic — the AWS load balancer
controller reads them to decide where it may place load balancers:

| Tag | On | Value |
| --- | --- | --- |
| `kubernetes.io/role/internal-elb` | private subnets | `1` |
| `kubernetes.io/role/elb` | public subnets | `1` |

## Adding your own

Per environment, in `live/<env>/main.tf`:

```hcl
  extra_tags = {
    DataClassification = "internal"
    Compliance         = "none"
    ExpiresAt          = "2027-01-01"
  }
```

## Turning tags on in Cost Explorer

Tags only appear in billing after you activate them, and activation is manual and one-time:

1. Sign in to the **management** account of your AWS Organization
2. **Billing and Cost Management → Cost allocation tags**
3. Under **User-defined cost allocation tags**, select `Project`, `Environment`, `CostCenter`, `Owner`
4. **Activate**

Data starts accumulating from the activation date; it is not retroactive. Do this on day one.

## Finding untagged resources

```bash
# everything tagged for this environment
aws resourcegroupstaggingapi get-resources \
  --tag-filters Key=Environment,Values=stage \
  --query 'length(ResourceTagMappingList)'

# resources with NO tags at all
aws resourcegroupstaggingapi get-resources \
  --query 'ResourceTagMappingList[?length(Tags)==`0`].ResourceARN' \
  --output table
```

Some things will legitimately show up untagged. EKS Auto Mode's EC2 instances and EBS volumes
are created by AWS, not Terraform, and do not inherit your tags by default — propagating tags to
them needs a custom NodeClass, which is a Kubernetes manifest rather than Terraform. The
Kubernetes-created NLB and its security groups are tagged by the load balancer controller with
its own scheme. A few AWS resource types simply do not support tags.

## A tag worth adding to prod

```hcl
  extra_tags = {
    Backup = "required"
  }
```

Then AWS Backup can select resources by tag instead of by a hand-maintained list, which is one
fewer list to forget to update.
