output "domain" {
  value = aws_route53_zone.domain.name
}

output "app_subdomain" {
  value = var.app_subdomain
}

output "argocd_subdomain" {
  value = var.argocd_subdomain
}

output "zone_id" {
  value = aws_route53_zone.domain.zone_id
}

output "hosted_zone_arn" {
  value = aws_route53_zone.domain.arn
}
