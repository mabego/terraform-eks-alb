resource "random_password" "master" {
  length  = 16
  special = false
}

resource "aws_rds_cluster_parameter_group" "eks_db_cluster_sg" {
  name   = "rds-cluster-pg"
  family = "aurora-mysql5.7"

  parameter {
    name  = "character_set_client"
    value = "utf8mb4"
  }

  parameter {
    name  = "character_set_connection"
    value = "utf8mb4"
  }

  parameter {
    name  = "character_set_database"
    value = "utf8mb4"
  }

  parameter {
    name  = "character_set_results"
    value = "utf8mb4"
  }

  parameter {
    name  = "character_set_server"
    value = "utf8mb4"
  }

  parameter {
    name  = "collation_connection"
    value = "utf8mb4_unicode_ci"
  }

  parameter {
    name  = "collation_server"
    value = "utf8mb4_unicode_ci"
  }
}

resource "aws_db_subnet_group" "main" {
  name       = "primary"
  subnet_ids = [var.subnets.database_a, var.subnets.database_b]
}

resource "aws_rds_cluster" "eks_db" {
  cluster_identifier              = "eks-aurora-cluster"
  database_name                   = "snippetbox"
  engine                          = "aurora-mysql"
  engine_version                  = "5.7.mysql_aurora.2.11.4"
  engine_mode                     = "serverless"
  db_subnet_group_name            = aws_db_subnet_group.main.name
  master_username                 = "web"
  master_password                 = random_password.master.result
  storage_encrypted               = true
  port                            = 3306
  skip_final_snapshot             = true
  vpc_security_group_ids          = [var.allow-db-access]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.eks_db_cluster_sg.name

  scaling_configuration {
    auto_pause               = true
    max_capacity             = 1
    min_capacity             = 1
    seconds_until_auto_pause = 300
    timeout_action           = "ForceApplyCapacityChange"
  }
}

resource "aws_secretsmanager_secret" "rds_credentials" {
  depends_on              = [aws_rds_cluster.eks_db]
  name                    = "${aws_rds_cluster.eks_db.database_name}/${aws_rds_cluster.eks_db.engine}"
  recovery_window_in_days = 0  # delete secret immediately with a destroy
}

resource "aws_secretsmanager_secret_version" "rds_credentials" {
  secret_id     = aws_secretsmanager_secret.rds_credentials.id
  secret_string = <<EOF
{
  "dbname": "${aws_rds_cluster.eks_db.database_name}",
  "host": "${aws_rds_cluster.eks_db.endpoint}",
  "password": "${aws_rds_cluster.eks_db.master_password}",
  "username": "${aws_rds_cluster.eks_db.master_username}"
}
EOF
}
