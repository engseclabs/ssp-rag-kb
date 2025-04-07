#!/bin/bash

CLUSTER_ARN=$1
SECRET_ARN=$2
DATABASE_NAME=$3

aws rds-data execute-statement \
    --resource-arn ${CLUSTER_ARN} \
    --database ${DATABASE_NAME} \
    --secret-arn ${SECRET_ARN} \
    --sql "CREATE EXTENSION IF NOT EXISTS vector;"

aws rds-data execute-statement \
    --resource-arn ${CLUSTER_ARN} \
    --database ${DATABASE_NAME} \
    --secret-arn ${SECRET_ARN} \
    --sql "CREATE SCHEMA IF NOT EXISTS bedrock;"

aws rds-data execute-statement \
    --resource-arn ${CLUSTER_ARN} \
    --database ${DATABASE_NAME} \
    --secret-arn ${SECRET_ARN} \
    --sql "CREATE TABLE IF NOT EXISTS bedrock.kb_table (id SERIAL PRIMARY KEY, text TEXT, metadata JSONB, vector vector(1536));"