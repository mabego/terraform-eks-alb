output "rds_credentials" {
  value = aws_secretsmanager_secret_version.rds_credentials.arn
}

output "secrets_name" {
  value = aws_secretsmanager_secret.rds_credentials.name
}