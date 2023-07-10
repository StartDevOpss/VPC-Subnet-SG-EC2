// Configure the AWS Provider
provider "aws" {
  region     = "us-east-1"
}

# 1) Create VPC
resource "aws_vpc" "A" {
  cidr_block = "10.0.0.0/16"
  
  tags = {
    name = "Codepoint"
  }
}

# 2) Create Internet Gateway
resource "aws_internet_gateway" "GW_Codepoint" {
  vpc_id = aws_vpc.A.id

  tags = {
    Name = "IG_Codepoint"
  }
}


# 3) Create Route Table
resource "aws_route_table" "RT_Codepoint" {
  vpc_id = aws_vpc.A.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.GW_Codepoint.id
  }

  route {
    ipv6_cidr_block = "::/0"
    gateway_id = aws_internet_gateway.GW_Codepoint.id
  }

  tags = {
    Name = "RT_Codepoint"
  }
}

# 4) Create Subnet
resource "aws_subnet" "Subnet_Codepoint" {
  vpc_id     = aws_vpc.A.id
  cidr_block = "10.0.0.0/24"
  availability_zone = "us-east-1a"
  depends_on = [aws_internet_gateway.GW_Codepoint]

  tags = {
    Name = "Subnet_Codepoint"
  }
}

# 5) Associate Subnet with Route Table
resource "aws_route_table_association" "RT_to_Subnet" {
  subnet_id      = aws_subnet.Subnet_Codepoint.id
  route_table_id = aws_route_table.RT_Codepoint.id
}


# 6) Create Security Group to allow ports: 22, 80, 443
resource "aws_security_group" "SG_Codepoint" {
  name        = "SG_Codepoint"
  description = "Allow SSH, HTTP, HTTPS inbound traffic"
  vpc_id      = aws_vpc.A.id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP from VPC"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH from VPC"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "SG_Codepoint"
  }
}

# 7) Assign ENI with IP
resource "aws_network_interface" "ENI_A" {
subnet_id = aws_subnet.Subnet_Codepoint.id
private_ips = ["10.0.0.10"]
security_groups = [aws_security_group.SG_Codepoint.id]
}


# 8) Assign Elastic IP to ENI
resource "aws_eip" "EIP_A" {
  vpc                       = true
  network_interface         = aws_network_interface.ENI_A.id
  associate_with_private_ip = "10.0.0.10"
  depends_on                = [aws_internet_gateway.GW_Codepoint, aws_instance.Instance_A]
  
  tags = {
    Name = "EIP_A"
  }
}


# 9) Creat IAM Role to acces S3
resource "aws_iam_role" "EC2-S3" {
  name = "EC2-S3"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF

  tags = {
      Name = "EC2-S3"
  }
}

// IAM Profile
resource "aws_iam_instance_profile" "EC2-S3_Profile" {
  name = "EC2-S3_Profile"
  role = "${aws_iam_role.EC2-S3.name}"
}

// IAM Policy
resource "aws_iam_role_policy" "EC2-S3_Policy" {
  name = "test_policy"
  role = "${aws_iam_role.EC2-S3.id}"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:*"
      ],
      "Resource": "*"
    }
  ]
}
EOF
 
}


# 10) Create Linux Server and Install/Enable Apache2
resource "aws_instance" "Instance_A" {
  ami                  = "ami-003d3d03cfe1b0468" 
  instance_type        = "t2.micro"
  availability_zone    = "us-east-1a"
  key_name             = "Codepoint"
  iam_instance_profile = "${aws_iam_instance_profile.EC2-S3_Profile.name}"
  
  network_interface {
    device_index = 0
    network_interface_id = aws_network_interface.ENI_A.id
  }

  user_data = <<-EOF
    #!/bin/bash
    sudo yum update -y
    sudo yum install -y httpd.x86_64
    sudo systemctl start httpd.service
    sudo systemctl enable httpd.service
    sudo aws s3 sync s3://awsbucketbeta00/website /var/www/html 
  EOF

  tags = {
    Name = "Codepoint_1.0"
  }
}

# 11) Enable VCP Endpoint
resource "aws_vpc_endpoint" "s3" {
  vpc_id       = aws_vpc.A.id
  service_name = "com.amazonaws.us-east-1.s3"

  tags = {
    Environment = "test"
  }
}

