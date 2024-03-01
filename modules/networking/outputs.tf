output "subnets" {
  value = {
    private_a = aws_subnet.private_a.id
    private_b = aws_subnet.private_b.id
    public_a = aws_subnet.public_a.id
    public_b = aws_subnet.public_b.id
    database_a = aws_subnet.database_a.id
    database_b = aws_subnet.database_b.id
  }
}

output "allow-db-access" {
  value = aws_security_group.allow-db-access.id
}
