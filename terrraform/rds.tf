# resource "random_password" "db_password" {
#   length = 16
#   special = false
# }

# resource "aws_db_subnet_group" "default" {
#   name = "kubeflow-${var.vpc_name}-db"

#   subnet_ids = var.private_subnets_ids

#   tags = {
#     Name = "Kubeflow DB subnet group"
#   }
# }

# resource "aws_db_instance" "kubeflow-db-instance-1" {
#   identifier = "kubeflow-${var.vpc_name}-db"
#   allocated_storage = 20
#   storage_type = "gp2"
#   engine = "postgres"
#   engine_version = "12.5"
#   instance_class = var.db_instance_type
#   name = "kubeflow_db"
#   username = "postgres"
#   password = random_password.db_password.result

#   db_subnet_group_name = aws_db_subnet_group.default.name
#   vpc_security_group_ids = [
#     aws_security_group.pg_security_group.id
#   ]
# }

# locals {
#   server_subnet = var.private_subnets_ids[0]
# }