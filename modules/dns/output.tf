output "subdomain" {
  value = aws_route53_zone.subdomain.name
}

output "zone_id" {
  value = aws_route53_zone.subdomain.zone_id
}
