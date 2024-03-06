variable "namespace" {
  type = string
}

variable "domain" {
  default = "colawarrior.com" # update to use your domain
}

variable "app_subdomain" {
  default = "snippetbox"
}

variable "argocd_subdomain" {
  default = "argo"
}
