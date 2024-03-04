resource "aws_route53_zone" "subdomain" {
  name          = "${var.subdomain}.${var.domain}"
  force_destroy = true
}

resource "aws_route53_record" "subdomain_ns" {
  allow_overwrite = true
  name            = "${var.subdomain}.${var.domain}"
  type            = "NS"
  ttl             = 172800
  zone_id         = aws_route53_zone.subdomain.zone_id

  records = [
    aws_route53_zone.subdomain.name_servers[0],
    aws_route53_zone.subdomain.name_servers[1],
    aws_route53_zone.subdomain.name_servers[2],
    aws_route53_zone.subdomain.name_servers[3],
  ]
}

# Create Certificate

resource "aws_acm_certificate" "cert" {
  domain_name       = "${var.subdomain}.${var.domain}"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "cert" {
  for_each = {
    for dvo in aws_acm_certificate.cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  type            = each.value.type
  zone_id         = aws_route53_zone.subdomain.zone_id
  records         = [each.value.record]
  ttl             = 60
}

resource "aws_route53domains_registered_domain" "domain" {
  domain_name = var.domain

  dynamic "name_server" {
    for_each = aws_route53_zone.subdomain.name_servers

    content {
      name = name_server.value
    }
  }
}
