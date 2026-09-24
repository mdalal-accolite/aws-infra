output "instance_id" { value = aws_instance.this.id }
output "private_ip" { value = aws_instance.this.private_ip }
output "role_arn" { value = aws_iam_role.this.arn }
output "connect_command" {
  value = "aws ssm start-session --target ${aws_instance.this.id}"
}
