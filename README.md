# SSP RAG Knowledge Base

Example Terraform configuration for building a FedRAMP-compliant SSP editor using AWS Bedrock. Part of the [FedRAMP Labs](https://fedramplabs.com) project to demonstrate compliant AI implementations.

## What is this?

This Terraform creates an AWS Bedrock knowledge base that can help you analyze and edit your System Security Plan (SSP) while keeping your data within your AWS environment. It uses:

- AWS Bedrock for AI capabilities
- Aurora Serverless v2 for vector storage
- S3 for document storage

## Usage

1. Copy NIST 800-53 control files from [GraphGRC](https://github.com/alsmola/graphgrc/blob/main/nist80053/index.md) to here: `nist80053/*.md`
2. Copy and customize the variables:
```bash
cp terraform.tfvars.example terraform.tfvars
```
3. Update your tfvars file with:
   - VPC ID
   - Subnet IDs (need two)
   - Database password
4. Deploy:
```bash
terraform init
terraform apply
```
5. Upload your SSP to the created S3 bucket
6. Use AWS Bedrock to ask questions about your SSP and get AI-powered suggestions

## Security Note

All data stays within your AWS environment. The AI processing happens through AWS Bedrock, which has FedRAMP authorization.

## More Information

Read the full blog post at [link] or visit [FedRAMP Labs](https://fedramplabs.com) for more examples of FedRAMP-compliant cloud implementations.