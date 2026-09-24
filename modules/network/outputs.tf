output "vpc_id" {
  value = aws_vpc.this.id
}

output "vpc_cidr" {
  value = aws_vpc.this.cidr_block
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "availability_zones" {
  value = local.azs
}

output "sg_rds_id" {
  value = aws_security_group.rds.id
}

output "sg_rds_proxy_id" {
  value = aws_security_group.rds_proxy.id
}

output "sg_redis_id" {
  value = aws_security_group.redis.id
}

output "sg_ec2_tools_id" {
  value = aws_security_group.ec2_tools.id
}

output "sg_client_vpn_id" {
  value = aws_security_group.client_vpn.id
}

output "nat_gateway_public_ips" {
  description = "Static egress IPs - give these to any third party that needs to allowlist you."
  value       = aws_eip.nat[*].public_ip
}
