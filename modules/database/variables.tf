variable "namespace" {
  type = string
}

variable "subnets" {
  type = object({
    database_a = string
    database_b = string
  })
}

variable "allow-db-access" {
  type = string
}
