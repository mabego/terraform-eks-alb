output "subdomain" {
  value = aws_route53_zone.subdomain.name
}

output "zone_id" {
  value = aws_route53_zone.subdomain.zone_id
}

output "hosted_zone_arn" {
  value = aws_route53_zone.subdomain.arn
}