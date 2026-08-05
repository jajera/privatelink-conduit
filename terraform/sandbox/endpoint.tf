resource "aws_security_group" "endpoint" {
  name        = "${local.name_prefix}-vpce"
  description = "PrivateLink interface endpoint"
  vpc_id      = aws_vpc.this.id

  tags = {
    Name = "${local.name_prefix}-vpce-sg"
  }
}

resource "aws_security_group_rule" "endpoint_ingress_http" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = [var.vpc_cidr]
  security_group_id = aws_security_group.endpoint.id
  description       = "HTTP from sandbox VPC"
}

resource "aws_security_group_rule" "endpoint_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.endpoint.id
  description       = "Allow all egress"
}

resource "aws_vpc_endpoint" "conduit" {
  vpc_id              = aws_vpc.this.id
  service_name        = var.endpoint_service_name
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.endpoint.id]
  private_dns_enabled = false

  tags = {
    Name = "${local.name_prefix}-conduit-vpce"
  }
}

resource "aws_route53_zone" "conduit" {
  name = "conduit.internal"

  vpc {
    vpc_id = aws_vpc.this.id
  }

  tags = {
    Name = "${local.name_prefix}-conduit-zone"
  }
}

resource "aws_route53_record" "config" {
  zone_id = aws_route53_zone.conduit.zone_id
  name    = "config.conduit.internal"
  type    = "A"

  alias {
    name                   = aws_vpc_endpoint.conduit.dns_entry[0].dns_name
    zone_id                = aws_vpc_endpoint.conduit.dns_entry[0].hosted_zone_id
    evaluate_target_health = true
  }
}
