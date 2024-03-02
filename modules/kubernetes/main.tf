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


data "aws_eks_cluster_auth" "cluster" {
  name = var.cluster_name
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

################################################################################
# Create OpenID Connect Identity Provider for drivers
################################################################################

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

################################################################################
# AWS load balancer controller installation
################################################################################

# AWS load balancer controller IAM policy
# Template from https://github.com/kubernetes-sigs/aws-load-balancer-controller/docs/install/iam_policy.json
# Use the policy from the branch of the version you are installing.
resource "aws_iam_policy" "aws_load_balancer_controller" {
  policy = file("${path.module}/iam_policy.json")
  name   = "AWSLoadBalancerController"
}

# AWS load balancer controller trusted entities
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

# AWS load balancer controller IAM Role
resource "aws_iam_role" "aws_load_balancer_controller" {
  assume_role_policy = data.aws_iam_policy_document.aws_load_balancer_controller_assume_role_policy.json
  name               = "aws-load-balancer-controller"
}

# AWS load balancer controller policy attachment
resource "aws_iam_role_policy_attachment" "aws_load_balancer_controller_attach" {
  policy_arn = aws_iam_policy.aws_load_balancer_controller.arn
  role       = aws_iam_role.aws_load_balancer_controller.name
}

resource "helm_release" "aws_load_balancer_controller" {
  name             = "aws-load-balancer-controller"
  repository       = "https://aws.github.io/eks-charts"
  chart            = "aws-load-balancer-controller"
  namespace        = "kube-system"
  version          = "1.4.1"
  create_namespace = true

  set {
    name  = "clusterName"
    value = aws_eks_cluster.cluster.id
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

################################################################################
# Secrets store CSI driver installation and AWS Secrets Manager integration
################################################################################

# App deployment namespace
resource "kubernetes_namespace" "web-app" {
  metadata {
    name = "web-app"
  }
}

locals {
  secrets_sa = "web-app-sa"
}

# Secrets store CSI IAM policy
resource "aws_iam_policy" "secrets_csi" {
  name = "secrets-csi-policy"

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = [var.rds_credentials]
      }
    ]
  })
}

# Secrets store CSI trusted entities
data "aws_iam_policy_document" "secrets_csi_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks_oidc.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:${kubernetes_namespace.web-app.metadata[0].name}:${local.secrets_sa}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks_oidc.url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }

    principals {
      identifiers = [aws_iam_openid_connect_provider.eks_oidc.arn]
      type        = "Federated"
    }
  }
}

# Secrets store CSI IAM Role for the Kubernetes service account to access database credentials using AWS Secrets Manager
resource "aws_iam_role" "secrets_csi" {
  assume_role_policy = data.aws_iam_policy_document.secrets_csi_assume_role_policy.json
  name               = "secrets-csi-role"
}

# Secrets store CSI policy Attachment
resource "aws_iam_role_policy_attachment" "secrets_csi" {
  policy_arn = aws_iam_policy.secrets_csi.arn
  role       = aws_iam_role.secrets_csi.name
}

resource "helm_release" "secrets_store_csi_driver" {
  depends_on = [helm_release.aws_load_balancer_controller]
  name       = "secrets-store-csi-driver"
  namespace  = "kube-system"
  repository = "https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts"
  chart      = "secrets-store-csi-driver"
  version    = "1.3.1"

  set {
    name  = "syncSecret.enabled"
    value = true
  }
}

resource "helm_release" "secrets_store_csi_driver_provider_aws" {
  depends_on = [helm_release.aws_load_balancer_controller]
  name       = "aws-secrets-manager"
  namespace  = "kube-system"
  repository = "https://aws.github.io/secrets-store-csi-driver-provider-aws"
  chart      = "secrets-store-csi-driver-provider-aws"
  version    = "0.3.0"
}

# Secrets store CSI Kubernetes manifests

# Service Account
resource "kubectl_manifest" "secrets_csi_sa" {
  depends_on = [kubernetes_namespace.web-app]
  yaml_body  = <<YAML
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ${local.secrets_sa}
  namespace: web-app
  annotations:
    eks.amazonaws.com/role-arn: ${aws_iam_role.secrets_csi.arn}
YAML
}

# Secret Provider Class
resource "kubectl_manifest" "secret_csi_spc" {
  depends_on = [helm_release.secrets_store_csi_driver_provider_aws]
  yaml_body  = <<YAML
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: web-app-spc
  namespace: web-app
spec:
  provider: aws
  parameters:
    objects: |
      - objectName: ${var.secrets_name}
        objectType: secretsmanager
        objectAlias: db-secrets
  secretObjects:
    - secretName: db-secrets-vol
      type: Opaque
      data:
        - objectName: db-secrets
          key: DSN
YAML
}

################################################################################
# ExternalDNS installation
################################################################################

# ExternalDNS IAM access policy
resource "aws_iam_policy" "external_dns" {
  name = "external-dns-access-policy"

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"
        Action = [
          "route53:ChangeResourceRecordSets"
        ]
        Resource = ["arn:aws:route53:::hostedzone/*"] # TODO update to the hosted zone created in the dns module
      },
      {
        Effect = "Allow"
        Action = [
          "route53:ListHostedZones",
          "route53:ListResourceRecordSets"
        ]
        Resource = ["*"]
      }
    ]
  })
}

# ExternalDNS trusted entities
data "aws_iam_policy_document" "external_dns_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks_oidc.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:external-dns"]
    }

    principals {
      identifiers = [aws_iam_openid_connect_provider.eks_oidc.arn]
      type        = "Federated"
    }
  }
}

# ExternalDNS IAM Role
resource "aws_iam_role" "external_dns" {
  assume_role_policy = data.aws_iam_policy_document.external_dns_assume_role_policy.json
  name               = "external-dns-role"
}

# ExternalDNS policy attachment
resource "aws_iam_role_policy_attachment" "external_dns" {
  policy_arn = aws_iam_policy.external_dns.arn
  role       = aws_iam_role.external_dns.name
}

resource "helm_release" "external_dns" {
  name       = "external-dns"
  namespace  = "kube-system"
  repository = "https://kubernetes-sigs.github.io/external-dns"
  chart      = "external-dns"
  version    = "1.14.3"

  # Default values
  # https://github.com/kubernetes-sigs/external-dns/blob/master/charts/external-dns/values.yaml
  values = [
    <<EOF
serviceAccount:
  name: "external-dns"
  annotations:
    "eks.amazonaws.com/role-arn": ${aws_iam_role.external_dns.arn}
policy: sync
txtOwnerId: ${var.zone_id}
domainFilters: [${var.subdomain}]
provider: aws
extraArgs:
  - --aws-zone-type=public
EOF
  ]
}

################################################################################
# ArgoCD installation
################################################################################

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
