variable "namespace" {
  type = string
}

variable "cluster_name" {
  default = "ingress-alb"
}

variable "cluster_version" {
  default = "1.29"
}

variable "subnets" {
  type = object({
    cluster_a = string
    cluster_b = string
  })
}

variable "rds_credentials" {
  type = string
}

variable "secrets_name" {
  type = string
}

variable "domain" {
  type = string
}

variable "app_subdomain" {
  type = string
}

variable "argocd_subdomain" {
  type = string
}

variable "zone_id" {
  type = string
}

variable "hosted_zone_arn" {
  type = string
}
