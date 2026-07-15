provider "aws" {  
  region = "us-east-1"
}

resource "aws_budgets_budget" "titan_budget" {
  name         = "titan-fintech-monthly-budget"
  budget_type  = "COST"
  limit_amount = "10.00"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator = "GREATER_THAN"
    threshold           = 80
    threshold_type      = "PERCENTAGE"
    notification_type   = "ACTUAL"
    subscriber_email_addresses = ["kpriester88@gmail.com"]
  }
}

resource "random_id" "vault_id" {
  byte_length = 4
}

resource "aws_s3_bucket" "vault" {
  bucket = "titan-fintech-vault-kp-${random_id.vault_id.hex}"
}

# Ensure the bucket is private by default
resource "aws_s3_bucket_public_access_block" "vault_access" {
  bucket = aws_s3_bucket.vault.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# 1. The Trust Policy (AssumeRole)
data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "titan_role" {
  name               = "titan-ec2-vault-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
}

# 2. The Surgical Permission Policy
data "aws_iam_policy_document" "s3_write_only" {
  statement {
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.vault.arn}/*"]
  }
}

resource "aws_iam_policy" "vault_write_policy" {
  name   = "titan-vault-write-policy"
  policy = data.aws_iam_policy_document.s3_write_only.json
}

resource "aws_iam_role_policy_attachment" "attach_policy" {
  role       = aws_iam_role.titan_role.name
  policy_arn = aws_iam_policy.vault_write_policy.arn
}

resource "aws_iam_instance_profile" "titan_profile" {
  name = "titan-ec2-instance-profile"
  role = aws_iam_role.titan_role.name
}

# This tells Terraform: "Find me the latest Ubuntu 22.04 in WHATEVER region I am currently in"
data "aws_ami" "latest_ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

resource "aws_instance" "app" {
  # This dynamically pulls the correct ID for your region
  ami           = data.aws_ami.latest_ubuntu.id 
  instance_type = "t2.micro"
  
  iam_instance_profile = aws_iam_instance_profile.titan_profile.name

  tags = {
    Name = "Titan-FinTech-App-Server"
  }

  depends_on = [aws_iam_role_policy_attachment.attach_policy]
}