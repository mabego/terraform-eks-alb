Terraform modules that create an EKS cluster, an RDS Aurora database, VPC networking, and a Route 53 hosted zone, for a simple, tier-two [application deployment](https://github.com/mabego/snippetbox-deployment).

The Kubernetes module also installs the [AWS load balancer controller](https://github.com/mabego/terraform-eks-alb/blob/main/modules/kubernetes/main.tf#L136-L212), [secrets store CSI driver](https://github.com/mabego/terraform-eks-alb/blob/main/modules/kubernetes/main.tf#L214-L348), [ExternalDNS](https://github.com/mabego/terraform-eks-alb/blob/main/modules/kubernetes/main.tf#L350-L436), and [ArgoCD](https://github.com/mabego/terraform-eks-alb/blob/main/modules/kubernetes/main.tf#L438-L527) on the cluster with the Helm provider.

Database credentials are sent to AWS Secrets Manager in the [database module](https://github.com/mabego/terraform-eks-alb/blob/main/modules/database/main.tf#L75-L95) and accessed from the app using the [secrets store CSI driver](https://github.com/mabego/snippetbox-deployment/blob/main/rds-mysql/deployment.yaml#L18-L40). The web app creates the [database schema](https://github.com/mabego/snippetbox-mysql/tree/main/migrations/sql) and handles the [secret JSON object](https://github.com/mabego/snippetbox-mysql/blob/main/cmd/web/main.go#L37-L43).

The deployment domain and subdomains can be updated in the [dns module's variables](https://github.com/mabego/terraform-eks-alb/blob/main/modules/dns/variables.tf).

The AWS load balancer controller and ExternalDNS will deploy a load balancer and DNS records to allow external access for either application deployment or ArgoCD.

This repository does not use community modules, such as [terraform-aws-eks](https://github.com/terraform-aws-modules/terraform-aws-eks).