provider "aws" {
  region = "us-east-1"
}

# --- DATA SOURCES (Linked to iam_provided.tf resources) ---
data "aws_iam_role" "flow_log_role" {
  name = aws_iam_role.flow_log_role.name
}

data "aws_iam_instance_profile" "ssm_profile" {
  name = aws_iam_instance_profile.ssm_profile.name
}

data "aws_ami" "ubuntu" {
  most_recent = true
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  owners = ["099720109477"] # Canonical
}

# --- THE PERIMETER (VPC & Networking) ---
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "titan-prod-vpc"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true

  tags = {
    Name = "titan-public-subnet"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "titan-igw"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "titan-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# --- THE WIRETAP (CloudWatch & VPC Flow Logs) ---
resource "aws_cloudwatch_log_group" "flow_logs" {
  name              = "/tkh/titan-prod-vpc-logs"
  retention_in_days = 1
}

resource "aws_flow_log" "vpc_flow_log" {
  iam_role_arn    = data.aws_iam_role.flow_log_role.arn
  log_destination = aws_cloudwatch_log_group.flow_logs.arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.main.id
}

# --- THE ZERO TRUST COMPUTE (Security Group & Instance) ---
resource "aws_security_group" "zerotrust_sg" {
  name        = "titan-zerotrust-sg"
  description = "Zero trust SG with zero inbound and full outbound"
  vpc_id      = aws_vpc.main.id

  # ZERO inbound ports allowed
  ingress = []

  # Full outbound egress to allow SSM agent communication
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "titan-zerotrust-sg"
  }
}

resource "aws_instance" "app_server" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.zerotrust_sg.id]
  iam_instance_profile   = data.aws_iam_instance_profile.ssm_profile.name

  tags = {
    Name = "titan-prod-ec2"
  }
}