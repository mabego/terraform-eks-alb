output "configure_kubectl" {
  description = "Configure kubectl: make sure you're logged in with the correct AWS profile and run the following command to update your kubeconfig"
  value       = "aws eks update-kubeconfig --name ${module.kubernetes.cluster_name} --alias ${module.kubernetes.cluster_name} --region ${var.region}"
}