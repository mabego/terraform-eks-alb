output "aws_load_balancer_controller_role_arn" {
  value = aws_iam_role.aws_load_balancer_controller.arn
}

output "cluster_name" {
  value = var.cluster_name
}
