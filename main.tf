module "networking" {
  source    = "./modules/networking"
  namespace = var.namespace

  cluster_name = module.kubernetes.cluster_name
}

module "kubernetes" {
  source    = "./modules/kubernetes"
  namespace = var.namespace

  subnets = module.networking.subnets
}
