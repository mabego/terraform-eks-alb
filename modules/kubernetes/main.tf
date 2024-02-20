resource "aws_iam_role" "eks_cluster" {
  name = "eks-cluster-${var.cluster_name}"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "eks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY
}

resource "aws_iam_role_policy_attachment" "amazon_eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster.name
}

resource "aws_eks_cluster" "cluster" {
  name     = var.cluster_name
  version  = var.cluster_version
  role_arn = aws_iam_role.eks_cluster.arn

  vpc_config {
    subnet_ids = [
      var.subnets.private_a,
      var.subnets.private_b,
      var.subnets.public_a,
      var.subnets.public_b,
    ]
  }

  depends_on = [aws_iam_role_policy_attachment.amazon_eks_cluster_policy]
}

# Node Group

resource "aws_iam_role" "nodes" {
  name = "eks-node-group-nodes"

  assume_role_policy = jsonencode({
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
    Version = "2012-10-17"
  })
}

resource "aws_iam_role_policy_attachment" "amazon_eks_worker_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.nodes.name
}

resource "aws_iam_role_policy_attachment" "amazon_eks_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.nodes.name
}

resource "aws_iam_role_policy_attachment" "amazon_ec2_container_registry_read_only" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.nodes.name
}

resource "aws_eks_node_group" "private_nodes" {
  cluster_name    = aws_eks_cluster.cluster.name
  version         = var.cluster_version
  node_group_name = "private-nodes"
  node_role_arn   = aws_iam_role.nodes.arn

  subnet_ids = [
    var.subnets.private_a,
    var.subnets.private_b,
  ]

  capacity_type  = "ON_DEMAND"
  instance_types = ["t3.small"]
  ami_type       = "BOTTLEROCKET_x86_64"

  scaling_config {
    desired_size = 2
    max_size     = 3
    min_size     = 0
  }

  update_config {
    max_unavailable = 1
  }

  labels = {
    role = "general"
  }

  depends_on = [
    aws_iam_role_policy_attachment.amazon_eks_worker_node_policy,
    aws_iam_role_policy_attachment.amazon_eks_cni_policy,
    aws_iam_role_policy_attachment.amazon_ec2_container_registry_read_only,
  ]

  # Allow external changes without Terraform plan difference
  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }
}

# OpenID Connect Identity Provider for the ALB Controller

# Retrieve the TLS certificate for the EKS cluster and assigns it to the variable data.tls_certificate.eks
data "tls_certificate" "eks_tls_cert" {
  url = aws_eks_cluster.cluster.identity[0].oidc[0].issuer
}

# Allow IAM roles to trust and authenticate using the OpenID Connect (OIDC) protocol.
resource "aws_iam_openid_connect_provider" "eks_oidc" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks_tls_cert.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.cluster.identity[0].oidc[0].issuer
}

data "aws_iam_policy_document" "aws_load_balancer_controller_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks_oidc.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:aws-load-balancer-controller"]
    }

    principals {
      identifiers = [aws_iam_openid_connect_provider.eks_oidc.arn]
      type        = "Federated"
    }
  }
}

resource "aws_iam_role" "aws_load_balancer_controller" {
  assume_role_policy = data.aws_iam_policy_document.aws_load_balancer_controller_assume_role_policy.json
  name               = "aws-load-balancer-controller"
}

# IAM policy template from https://github.com/kubernetes-sigs/aws-load-balancer-controller/docs/install/iam_policy.json
# Only use policy from the branch of the version you are installing.
resource "aws_iam_policy" "aws_load_balancer_controller" {
  policy = file("${path.module}/iam_policy.json")
  name   = "AWSLoadBalancerController"
}

resource "aws_iam_role_policy_attachment" "aws_load_balancer_controller_attach" {
  role       = aws_iam_role.aws_load_balancer_controller.name
  policy_arn = aws_iam_policy.aws_load_balancer_controller.arn
}

# ALB Controller

resource "helm_release" "aws_load_balancer_controller" {
  name             = "aws-load-balancer-controller"
  repository       = "https://aws.github.io/eks-charts"
  chart            = "aws-load-balancer-controller"
  namespace        = "kube-system"
  version          = "1.4.1"
  create_namespace = true

  values = [
    file("${path.module}/ingress.yaml")
  ]

  set {
    name  = "clusterName"
    value = aws_eks_cluster.cluster.id
  }

  set {
    name  = "image.tag"
    value = "v2.7.1"
  }

  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.aws_load_balancer_controller.arn
  }

  depends_on = [
    aws_eks_node_group.private_nodes,
    aws_iam_role_policy_attachment.aws_load_balancer_controller_attach
  ]
}

# ArgoCD

resource "helm_release" "argocd" {
  depends_on       = [helm_release.aws_load_balancer_controller]
  name             = "argocd"
  namespace        = "argocd"
  create_namespace = true
  chart            = "argo-cd"
  repository       = "https://argoproj.github.io/argo-helm"
  version          = "5.35.0"
  values           = [file("${path.module}/argocd.yaml")]
  cleanup_on_fail  = true
}
