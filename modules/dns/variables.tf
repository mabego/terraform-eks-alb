variable "namespace" {
  type = string
}

variable "domain" {
  type = string
#  default = "example.com" # update to use your domain
}

variable "app_subdomain" {
  default = "snippetbox"
}

variable "argocd_subdomain" {
  default = "argo"
}
