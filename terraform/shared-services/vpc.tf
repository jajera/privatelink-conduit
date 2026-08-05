locals {
  name_prefix = "${var.project_name}-ss"
}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 2)
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${local.name_prefix}-vpc"
  }
}

# App + NLB subnets (2 AZs)
resource "aws_subnet" "app" {
  count = 2

  vpc_id            = aws_vpc.this.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 1)
  availability_zone = local.azs[count.index]

  tags = {
    Name = "${local.name_prefix}-app-${local.azs[count.index]}"
    Tier = "presentation-app"
  }
}

# Data subnets (2 AZs required for DB subnet group)
resource "aws_subnet" "data" {
  count = 2

  vpc_id            = aws_vpc.this.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 11)
  availability_zone = local.azs[count.index]

  tags = {
    Name = "${local.name_prefix}-data-${local.azs[count.index]}"
    Tier = "data"
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${local.name_prefix}-private-rt"
  }
}

resource "aws_route_table_association" "app" {
  count = 2

  subnet_id      = aws_subnet.app[count.index].id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "data" {
  count = 2

  subnet_id      = aws_subnet.data[count.index].id
  route_table_id = aws_route_table.private.id
}

# S3 gateway endpoint so AL2023 can dnf-install packages without NAT
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]

  tags = {
    Name = "${local.name_prefix}-s3-endpoint"
  }
}

resource "aws_security_group" "ssm_endpoints" {
  name        = "${local.name_prefix}-ssm-endpoints"
  description = "SSM VPC interface endpoints"
  vpc_id      = aws_vpc.this.id

  tags = {
    Name = "${local.name_prefix}-ssm-endpoints-sg"
  }
}

resource "aws_security_group_rule" "ssm_endpoints_ingress" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = [var.vpc_cidr]
  security_group_id = aws_security_group.ssm_endpoints.id
  description       = "HTTPS from VPC"
}

resource "aws_security_group_rule" "ssm_endpoints_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.ssm_endpoints.id
  description       = "Allow all egress"
}

locals {
  ssm_services = {
    ssm          = "com.amazonaws.${var.aws_region}.ssm"
    ssmmessages  = "com.amazonaws.${var.aws_region}.ssmmessages"
    ec2messages  = "com.amazonaws.${var.aws_region}.ec2messages"
  }
}

resource "aws_vpc_endpoint" "ssm" {
  for_each = local.ssm_services

  vpc_id              = aws_vpc.this.id
  service_name        = each.value
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.app[*].id
  security_group_ids  = [aws_security_group.ssm_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name = "${local.name_prefix}-${each.key}-endpoint"
  }
}
