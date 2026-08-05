data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-kernel-*-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

resource "aws_security_group" "test" {
  name        = "${local.name_prefix}-test"
  description = "Sandbox test EC2"
  vpc_id      = aws_vpc.this.id

  tags = {
    Name = "${local.name_prefix}-test-sg"
  }
}

resource "aws_security_group_rule" "test_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.test.id
  description       = "Allow all egress"
}

resource "aws_iam_role" "test" {
  name = "${local.name_prefix}-test-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "test_ssm" {
  role       = aws_iam_role.test.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "test" {
  name = "${local.name_prefix}-test-profile"
  role = aws_iam_role.test.name
}

resource "aws_instance" "test" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = "t3.nano"
  subnet_id              = aws_subnet.private[0].id
  vpc_security_group_ids = [aws_security_group.test.id]
  iam_instance_profile   = aws_iam_instance_profile.test.name

  user_data = <<-EOF
    #!/bin/bash
    set -euo pipefail
    # AL2023 ships curl-minimal; do not install curl (conflicts).
    dnf install -y amazon-ssm-agent || true
    systemctl enable --now amazon-ssm-agent || true
  EOF

  tags = {
    Name = "${local.name_prefix}-test"
  }

  depends_on = [
    aws_vpc_endpoint.s3,
    aws_vpc_endpoint.ssm,
  ]
}
