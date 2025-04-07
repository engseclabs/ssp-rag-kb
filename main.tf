terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.48"
    }
  }
  required_version = "~> 1.5"
}

provider "aws" {
  region = "us-east-1"
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

resource "aws_db_subnet_group" "ssp_rag_kb" {
  name       = "ssp-rag-kb"
  subnet_ids = var.subnet_ids
}

resource "aws_security_group" "ssp_rag_kb" {
  name        = "ssp-rag-kb-aurora"
  description = "Security group for Aurora Serverless v2 Knowledge Base"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.bedrock.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "bedrock" {
  name        = "ssp-rag-kb-bedrock"
  description = "Security group for Bedrock service"
  vpc_id      = var.vpc_id
}

resource "aws_rds_cluster_parameter_group" "ssp_rag_kb" {
  family = "aurora-postgresql15"
  name   = "ssp-rag-kb-params"

  parameter {
    name         = "shared_preload_libraries"
    value        = "pgvector"
    apply_method = "pending-reboot"
  }
}

resource "aws_rds_cluster" "ssp_rag_kb" {
  cluster_identifier              = "ssp-rag-kb"
  engine                         = "aurora-postgresql"
  engine_version                 = "15.4"
  database_name                  = "ssp_rag_kb"
  master_username                = "postgres"
  master_password                = var.db_password
  db_subnet_group_name           = aws_db_subnet_group.ssp_rag_kb.name
  skip_final_snapshot           = true
  vpc_security_group_ids         = [aws_security_group.ssp_rag_kb.id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.ssp_rag_kb.name

  serverlessv2_scaling_configuration {
    min_capacity = 0.5
    max_capacity = 16
  }

  iam_database_authentication_enabled = true

  lifecycle {
    ignore_changes = [
      engine_version
    ]
  }
}

resource "aws_rds_cluster_instance" "ssp_rag_kb" {
  cluster_identifier = aws_rds_cluster.ssp_rag_kb.id
  instance_class    = "db.serverless"
  engine            = aws_rds_cluster.ssp_rag_kb.engine
  engine_version    = aws_rds_cluster.ssp_rag_kb.engine_version

  lifecycle {
    ignore_changes = [
      engine_version
    ]
  }
}

resource "aws_s3_bucket" "ssp_rag_kb" {
  bucket        = var.s3_bucket_name
  force_destroy = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "ssp_rag_kb" {
  bucket = aws_s3_bucket.ssp_rag_kb.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "ssp_rag_kb" {
  bucket = aws_s3_bucket.ssp_rag_kb.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_secretsmanager_secret" "ssp_rag_kb" {
  name = "ssp-rag-kb-aurora-credentials"
}

resource "aws_secretsmanager_secret_version" "ssp_rag_kb" {
  secret_id = aws_secretsmanager_secret.ssp_rag_kb.id
  secret_string = jsonencode({
    username = aws_rds_cluster.ssp_rag_kb.master_username
    password = aws_rds_cluster.ssp_rag_kb.master_password
    engine   = "postgres"
    port     = 5432
    dbClusterIdentifier = aws_rds_cluster.ssp_rag_kb.cluster_identifier
    host     = aws_rds_cluster.ssp_rag_kb.endpoint
  })
}

resource "null_resource" "postgres_setup" {
  provisioner "local-exec" {
    command = "./database.sh ${aws_rds_cluster.ssp_rag_kb.arn} ${aws_secretsmanager_secret.ssp_rag_kb.arn} ${aws_rds_cluster.ssp_rag_kb.database_name}"
  }

  depends_on = [aws_rds_cluster_instance.ssp_rag_kb]
}

resource "aws_bedrockagent_knowledge_base" "ssp_rag_kb" {
  name        = "ssp-rag-kb"
  description = "Knowledge base for SSP RAG KB example"
  role_arn    = aws_iam_role.bedrock_kb_role.arn

  knowledge_base_configuration {
    type = "VECTOR"
    vector_knowledge_base_configuration {
      embedding_model_arn = "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-g1-text-02"
    }
  }

  storage_configuration {
    type = "RDS"
    rds_configuration {
      credentials_secret_arn = aws_secretsmanager_secret.ssp_rag_kb.arn
      database_name         = aws_rds_cluster.ssp_rag_kb.database_name
      resource_arn          = aws_rds_cluster.ssp_rag_kb.arn
      table_name            = "bedrock.kb_table"
      field_mapping {
        metadata_field     = "metadata"
        primary_key_field  = "id"
        text_field         = "text"
        vector_field       = "vector"
      }
    }
  }

  depends_on = [null_resource.postgres_setup]
}

resource "aws_bedrockagent_data_source" "ssp_rag_kb" {
  knowledge_base_id = aws_bedrockagent_knowledge_base.ssp_rag_kb.id
  name             = aws_s3_bucket.ssp_rag_kb.bucket

  data_source_configuration {
    type = "S3"
    s3_configuration {
      bucket_arn = aws_s3_bucket.ssp_rag_kb.arn
    }
  }

  data_deletion_policy = "RETAIN"
}

resource "aws_iam_role" "bedrock_kb_role" {
  name = "BedrockExecutionRoleForKnowledgeBase-ssp-rag-kb"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "bedrock.amazonaws.com"
      }
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = data.aws_caller_identity.current.account_id
        }
        ArnLike = {
          "aws:SourceArn" = "arn:aws:bedrock:us-east-1:${data.aws_caller_identity.current.account_id}:knowledge-base/*"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "bedrock_kb_policy" {
  name = "BedrockKBPolicy-ssp-rag-kb"
  role = aws_iam_role.bedrock_kb_role.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["bedrock:InvokeModel"]
        Resource = "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-g1-text-02"
      },
      {
        Effect = "Allow"
        Action = ["rds:DescribeDBClusters"]
        Resource = aws_rds_cluster.ssp_rag_kb.arn
      },
      {
        Effect = "Allow"
        Action = [
          "rds-data:BatchExecuteStatement",
          "rds-data:ExecuteStatement"
        ]
        Resource = aws_rds_cluster.ssp_rag_kb.arn
      },
      {
        Effect = "Allow"
        Action = "s3:ListBucket"
        Resource = aws_s3_bucket.ssp_rag_kb.arn
      },
      {
        Effect = "Allow"
        Action = "s3:GetObject"
        Resource = "${aws_s3_bucket.ssp_rag_kb.arn}/*"
      },
      {
        Effect = "Allow"
        Action = "secretsmanager:GetSecretValue"
        Resource = aws_secretsmanager_secret.ssp_rag_kb.arn
      }
    ]
  })
}