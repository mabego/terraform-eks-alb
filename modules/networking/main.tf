# VPC

data "aws_availability_zones" "available" {}

locals {
  vpc_cidr = "10.0.0.0/16"
  asz = slice(data.aws_availability_zones.available.names, 0, 4)
}

resource "aws_vpc" "eks_vpc" {
  cidr_block = local.vpc_cidr

  enable_dns_hostnames = true

  tags = {
    Name = "eks_vpc"
  }
}

# Subnets

resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.eks_vpc.id
#  cidr_block        = cidrsubnet(local.vpc_cidr, 8, 1)
  cidr_block        = "10.0.1.0/24"
#  availability_zone = "us-west-2a"
  availability_zone = local.asz[0]

  tags = {
    "Name"                                      = "private-a"
    "kubernetes.io/role/internal-elb"           = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }
}

resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.eks_vpc.id
#  cidr_block        = cidrsubnet(local.vpc_cidr, 8, 2)
  cidr_block        = "10.0.2.0/24"
  availability_zone = local.asz[1]

  tags = {
    "Name"                                      = "private-b"
    "kubernetes.io/role/internal-elb"           = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }
}

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.eks_vpc.id
#  cidr_block              = cidrsubnet(local.vpc_cidr, 8, 101)
  cidr_block              = "10.0.101.0/24"
  availability_zone       = local.asz[2]
  map_public_ip_on_launch = true

  tags = {
    "Name"                                      = "public-a"
    "kubernetes.io/role/elb"                    = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.eks_vpc.id
#  cidr_block              = cidrsubnet(local.vpc_cidr, 8, 102)
  cidr_block              = "10.0.102.0/24"
  availability_zone       = local.asz[3]
  map_public_ip_on_launch = true

  tags = {
    "Name"                                      = "public-b"
    "kubernetes.io/role/elb"                    = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
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

resource "aws_route_table" "private" {
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

resource "aws_route_table_association" "private_a" {
  subnet_id      = aws_subnet.private_a.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_b" {
  subnet_id      = aws_subnet.private_b.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}