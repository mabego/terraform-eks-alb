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
    private_a = string
    private_b = string
    public_a = string
    public_b = string
  })
}

variable "rds_credentials" {
  type = string
}

variable "secrets_name" {
  type = string
}

variable "subdomain" {
  type = string
}

variable "zone_id" {
  type = string
}
