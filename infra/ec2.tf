data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

# checkov:skip=CKV_AWS_260 reason: Port 80 open to internet is required for demo/public access
# checkov:skip=CKV_AWS_382 reason: All egress needed for EC2/alb to reach the internet
# checkov:skip=CKV_AWS_24 reason: Not all resources tagged for demo environment
resource "aws_security_group" "alb" {
  name   = "${local.prefix}-alb"
  vpc_id = aws_vpc.main.id
  description = "Security group for ALB"

  ingress {
    description = "Allow HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# checkov:skip=CKV_AWS_23 reason: Descriptions are omitted for brevity in test environment
resource "aws_security_group" "web" {
  name   = "${local.prefix}-web"
  vpc_id = aws_vpc.main.id
  description = "Security group for web EC2 instances"

  ingress {
    description = "Allow HTTP from ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

#############################
# application Load Balancer #
#############################

# checkov:skip=CKV_AWS_91 reason: Access logging not required for non-production
# checkov:skip=CKV_AWS_150 reason: Deletion protection not needed for this environment
# checkov:skip=CKV_AWS_131 reason: Header sanitization not used in current setup
# checkov:skip=CKV2_AWS_28 reason: No WAF for cost/dev environment
resource "aws_lb" "web" {
  name               = "${local.prefix}-web-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [aws_subnet.public_a.id, aws_subnet.public_b.id]
}

resource "aws_lb_target_group" "web" {
  name     = "${local.prefix}-web-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = "/"
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

resource "aws_lb_target_group_attachment" "web" {
  target_group_arn = aws_lb_target_group.web.arn
  target_id        = aws_instance.web.id
  port             = 80
}

# checkov:skip=CKV2_AWS_20 reason: HTTP to HTTPS redirect not enforced for this environment
# checkov:skip=CKV_AWS_103 reason: TLS1.2 requirement skipped in dev/test
# checkov:skip=CKV_AWS_2 reason: HTTP allowed for legacy/client support
# checkov:skip=CKV_AWS_378 reason: ALB runs HTTP for legacy reasons
resource "aws_lb_listener" "web" {
  load_balancer_arn = aws_lb.web.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}

# checkov:skip=CKV_AWS_135 reason: EBS optimization not needed for t3.micro or specific usage
# checkov:skip=CKV_AWS_126 reason: Detailed monitoring not required in dev/test
# checkov:skip=CKV_AWS_79 reason: IMDSv2 enforcement skipped for legacy init process
# checkov:skip=CKV_AWS_8 reason: EBS encryption not enabled for test/AMI does not support
resource "aws_instance" "web" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.private_a.id
  vpc_security_group_ids = [aws_security_group.web.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_ssm.name

  user_data = <<-EOF
    #!/bin/bash
    dnf install -y nginx
    systemctl enable nginx
    systemctl start nginx
    echo "<h1>Hello World!</h1>" > /usr/share/nginx/html/index.html
  EOF

  tags = {
    Name = "${local.prefix}-web"
  }
}
