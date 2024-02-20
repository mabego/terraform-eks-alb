output "subnets" {
  value = {
    private_a = aws_subnet.private_a.id
    private_b = aws_subnet.private_b.id
    public_a = aws_subnet.public_a.id
    public_b = aws_subnet.public_b.id
  }
}