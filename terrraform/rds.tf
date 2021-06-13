resource "random_password" "db_password" {
  length = 16
  special = false
}

resource "aws_security_group" "pg_security_group" {
  name = "argoflow_db_security_group"
  vpc_id = module.vpc.vpc_id
}

resource "aws_security_group_rule" "allow_postgres_inbound" {
  type = "ingress"
  from_port = 5432
  to_port = 5432
  protocol = "tcp"
  security_group_id = aws_security_group.pg_security_group.id
  # Only allow from eks cluster
  source_security_group_id = module.eks.cluster_primary_security_group_id
}

resource "aws_db_subnet_group" "default" {
  name = "argoflow-${module.vpc.name}-db"
  subnet_ids = module.vpc.private_subnets

  tags = {
    Name = "Argoflow DB subnet group"
  }
}

resource "aws_db_instance" "argoflow-db-instance" {
  identifier = "argoflow-${module.vpc.name}-db"
  allocated_storage = 20
  storage_type = "gp2"
  engine = "postgres"
  engine_version = "12.5"
  instance_class = var.db_instance_type
  name = "argoflow_db"
  username = "postgres"
  password = random_password.db_password.result

  db_subnet_group_name = aws_db_subnet_group.default.name
  vpc_security_group_ids = [
    aws_security_group.pg_security_group.id
  ]
}