terraform {
  required_version = ">= 1.3"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.37"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.12"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
      version = "2.26.0"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.7.0"
    }
  }
}

provider "helm" {
  kubernetes {
    host                   = aws_eks_cluster.cluster.endpoint
    cluster_ca_certificate = base64decode(aws_eks_cluster.cluster.certificate_authority[0].data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      args        = ["eks", "get-token", "--cluster-name", aws_eks_cluster.cluster.id]
      command     = "aws"
    }
  }
}

provider "kubernetes" {
  host                   = aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(aws_eks_cluster.cluster.certificate_authority[0].data)
  # token                  = data.aws_eks_cluster_auth.cluster.token
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    args        = ["eks", "get-token", "--cluster-name", aws_eks_cluster.cluster.id]
    command     = "aws"
  }
}

provider "kubectl" {
  host                   = aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(aws_eks_cluster.cluster.certificate_authority[0].data)
  load_config_file       = false
#  token                  = data.aws_eks_cluster_auth.cluster.token
   exec {
     api_version = "client.authentication.k8s.io/v1beta1"
     args        = ["eks", "get-token", "--cluster-name", aws_eks_cluster.cluster.id]
     command     = "aws"
   }
}