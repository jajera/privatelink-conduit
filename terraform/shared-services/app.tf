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

resource "aws_security_group" "app" {
  name        = "${local.name_prefix}-app"
  description = "Config API app tier"
  vpc_id      = aws_vpc.this.id

  tags = {
    Name = "${local.name_prefix}-app-sg"
  }
}

resource "aws_security_group_rule" "app_ingress_vpc_http" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = [var.vpc_cidr]
  security_group_id = aws_security_group.app.id
  description       = "HTTP from VPC (NLB / health checks)"
}

resource "aws_security_group_rule" "app_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.app.id
  description       = "Allow all egress"
}

resource "aws_iam_role" "app" {
  name = "${local.name_prefix}-app-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "app_ssm" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "app" {
  name = "${local.name_prefix}-app-profile"
  role = aws_iam_role.app.name
}

resource "aws_instance" "app" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.app[0].id
  vpc_security_group_ids = [aws_security_group.app.id]
  iam_instance_profile   = aws_iam_instance_profile.app.name

  user_data = templatefile("${path.module}/templates/app_userdata.sh.tftpl", {
    db_host     = aws_db_instance.this.address
    db_port     = tostring(aws_db_instance.this.port)
    db_name     = aws_db_instance.this.db_name
    db_user     = aws_db_instance.this.username
    db_password = random_password.db.result
  })

  user_data_replace_on_change = true

  tags = {
    Name = "${local.name_prefix}-app"
    Tier = "application"
  }

  depends_on = [
    aws_vpc_endpoint.s3,
    aws_vpc_endpoint.ssm,
    aws_db_instance.this,
  ]
}
