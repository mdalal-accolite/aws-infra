resource "aws_cloudwatch_log_group" "this" {
  name              = "/aws/client-vpn/${var.name_prefix}"
  retention_in_days = var.log_retention_days

  tags = var.tags
}

resource "aws_cloudwatch_log_stream" "this" {
  name           = "connections"
  log_group_name = aws_cloudwatch_log_group.this.name
}

resource "aws_ec2_client_vpn_endpoint" "this" {
  description            = "${var.name_prefix} client VPN"
  server_certificate_arn = var.server_certificate_arn
  client_cidr_block      = var.client_cidr_block
  split_tunnel           = true
  transport_protocol     = "udp"
  vpn_port               = 443
  vpc_id                 = var.vpc_id
  security_group_ids     = var.security_group_ids

  authentication_options {
    type                       = "certificate-authentication"
    root_certificate_chain_arn = var.client_root_certificate_chain_arn
  }

  connection_log_options {
    enabled               = true
    cloudwatch_log_group  = aws_cloudwatch_log_group.this.name
    cloudwatch_log_stream = aws_cloudwatch_log_stream.this.name
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-vpn" })
}

resource "aws_ec2_client_vpn_network_association" "this" {
  count = length(var.subnet_ids)

  client_vpn_endpoint_id = aws_ec2_client_vpn_endpoint.this.id
  subnet_id              = var.subnet_ids[count.index]
}

resource "aws_ec2_client_vpn_authorization_rule" "vpc" {
  client_vpn_endpoint_id = aws_ec2_client_vpn_endpoint.this.id
  target_network_cidr    = var.vpc_cidr
  authorize_all_groups   = true
  description            = "Allow VPN clients to reach the whole VPC"
}
