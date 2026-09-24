output "project" { value = local.project }
output "environment" { value = var.environment }
output "name_prefix" { value = local.name_prefix }
output "secret_prefix" { value = local.secret_prefix }
output "state_bucket" { value = local.state_bucket }
output "tags" { value = local.tags }

# The whole per-environment settings object.
output "env" { value = local.env }
