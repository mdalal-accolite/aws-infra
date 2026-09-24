data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

resource "aws_key_pair" "this" {
  count = var.public_key_openssh == "" ? 0 : 1

  key_name   = "${var.name_prefix}-tools-ec2-key"
  public_key = var.public_key_openssh

  tags = var.tags
}

###############################################################################
# Instance profile - SSM Session Manager is the only access path
###############################################################################
resource "aws_iam_role" "this" {
  name = "${var.name_prefix}-tools-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "cloudwatch" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "this" {
  name = "${var.name_prefix}-tools-ec2-profile"
  role = aws_iam_role.this.name

  tags = var.tags
}

resource "aws_instance" "this" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = var.security_group_ids
  iam_instance_profile   = aws_iam_instance_profile.this.name
  key_name               = var.public_key_openssh == "" ? null : aws_key_pair.this[0].key_name

  associate_public_ip_address = false # private subnet, egress via NAT

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
    encrypted   = true # dev's volume is unencrypted; fixed here
    tags        = merge(var.tags, { Name = "${var.name_prefix}-tools-ec2-volume" })
  }

  metadata_options {
    http_tokens                 = "required" # IMDSv2 only
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 2
  }

  monitoring = true

  tags = merge(var.tags, {
    Name      = "${var.name_prefix}-tools-ec2"
    Component = "tools"
    Service   = "ec2"
    Tier      = "private"
    Purpose   = "test-case-management (KiwiTCMS)"
  })

  lifecycle {
    ignore_changes = [ami]
  }
}
