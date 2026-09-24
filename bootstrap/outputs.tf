output "account_id" {
  value = data.aws_caller_identity.current.account_id
}

output "state_bucket" {
  description = "Put this in live/<env>/backend.hcl"
  value       = aws_s3_bucket.state.id
}

output "tf_plan_role_arn" {
  description = "Put this in the GitHub repo variable AWS_TF_PLAN_ROLE_<ENV>"
  value       = aws_iam_role.tf_plan.arn
}

output "tf_apply_role_arn" {
  description = "Put this in the GitHub repo variable AWS_TF_APPLY_ROLE_<ENV>"
  value       = aws_iam_role.tf_apply.arn
}

output "next_steps" {
  value = <<-EOT
    1. Copy state_bucket below into envs/${var.environment}.backend.hcl (the bucket
       name contains a random token, so it is not predictable - you must copy it).
    2. Copy the two role ARNs into GitHub repository VARIABLES (not secrets):
         AWS_TF_PLAN_ROLE_${upper(var.environment)}  = <tf_plan_role_arn>
         AWS_TF_APPLY_ROLE_${upper(var.environment)} = <tf_apply_role_arn>
    3. Confirm config/main.tf has the right account_id for ${var.environment}.
    4. Commit envs/${var.environment}.backend.hcl and bootstrap/terraform.tfstate.
  EOT
}
