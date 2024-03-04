# VPC

data "aws_availability_zones" "available" {}

locals {
  vpc_cidr = "10.0.0.0/16"
  asz      = slice(data.aws_availability_zones.available.names, 0, 4)
}

resource "aws_vpc" "eks_vpc" {
  cidr_block = local.vpc_cidr

  enable_dns_hostnames = true

  tags = {
    Name = "eks_vpc"
  }
}

# Subnets

# Cluster subnets are private but will be used with an external load balancer
resource "aws_subnet" "cluster_a" {
  vpc_id            = aws_vpc.eks_vpc.id
  #  cidr_block        = cidrsubnet(local.vpc_cidr, 8, 1)
  cidr_block        = "10.0.1.0/24"
  #  availability_zone = "us-west-2a"
  availability_zone = local.asz[0]

  tags = {
    "Name"                                      = "cluster-a"
    #    "kubernetes.io/role/internal-elb"           = "1"
    "kubernetes.io/role/elb"                    = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }
}

resource "aws_subnet" "cluster_b" {
  vpc_id            = aws_vpc.eks_vpc.id
  #  cidr_block        = cidrsubnet(local.vpc_cidr, 8, 2)
  cidr_block        = "10.0.2.0/24"
  availability_zone = local.asz[1]

  tags = {
    "Name"                                      = "cluster-b"
    #    "kubernetes.io/role/internal-elb"           = "1"
    "kubernetes.io/role/elb"                    = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }
}

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.eks_vpc.id
  cidr_block              = "10.0.101.0/24"
  availability_zone       = local.asz[2]
  map_public_ip_on_launch = true

  tags = {
    "Name"                                      = "public-a"
    "kubernetes.io/role/elb"                    = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.eks_vpc.id
  cidr_block              = "10.0.102.0/24"
  availability_zone       = local.asz[3]
  map_public_ip_on_launch = true

  tags = {
    "Name"                                      = "public-b"
    "kubernetes.io/role/elb"                    = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

resource "aws_subnet" "database_a" {
  vpc_id            = aws_vpc.eks_vpc.id
  cidr_block        = "10.0.10.0/24"
  availability_zone = local.asz[0]

  tags = {
    "Name" = "database-a"
  }
}

resource "aws_subnet" "database_b" {
  vpc_id            = aws_vpc.eks_vpc.id
  cidr_block        = "10.0.11.0/24"
  availability_zone = local.asz[1]

  tags = {
    "Name" = "database-b"
  }
}

# Gateways

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.eks_vpc.id

  tags = {
    Name = "igw"
  }
}

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "nat"
  }
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_a.id

  tags = {
    Name = "nat"
  }

  depends_on = [aws_internet_gateway.igw]
}

# Routes

resource "aws_route_table" "cluster" {
  vpc_id = aws_vpc.eks_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = {
    Name = "private"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.eks_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "public"
  }
}

resource "aws_route_table_association" "cluster_a" {
  subnet_id      = aws_subnet.cluster_a.id
  route_table_id = aws_route_table.cluster.id
}

resource "aws_route_table_association" "cluster_b" {
  subnet_id      = aws_subnet.cluster_b.id
  route_table_id = aws_route_table.cluster.id
}

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

# Database Security Group

resource "aws_security_group" "allow-db-access" {
  name   = "rds_sg"
  vpc_id = aws_vpc.eks_vpc.id

  ingress {
    from_port   = "3306"
    to_port     = "3306"
    protocol    = "tcp"
    cidr_blocks = [aws_subnet.cluster_a.cidr_block, aws_subnet.cluster_b.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "rds_sg"
  }
}
