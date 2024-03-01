module "networking" {
  source    = "./modules/networking"
  namespace = var.namespace

  cluster_name = module.kubernetes.cluster_name
}

module "database" {
  source = "./modules/database"
  namespace = var.namespace

  subnets = module.networking.subnets
  allow-db-access = module.networking.allow-db-access
}

module "kubernetes" {
  source    = "./modules/kubernetes"
  namespace = var.namespace

  subnets = module.networking.subnets
  rds_credentials = module.database.rds_credentials
  secrets_name = module.database.secrets_name
}
