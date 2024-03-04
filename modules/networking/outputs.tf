output "subnets" {
  value = {
    cluster_a = aws_subnet.cluster_a.id
    cluster_b = aws_subnet.cluster_b.id
    database_a = aws_subnet.database_a.id
    database_b = aws_subnet.database_b.id
  }
}

output "allow-db-access" {
  value = aws_security_group.allow-db-access.id
}
