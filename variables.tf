variable "vpc_id" {
  description = "VPC ID where resources will be created"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs for the Aurora cluster"
  type        = list(string)
}

variable "db_password" {
  description = "Master password for the Aurora cluster"
  type        = string
  sensitive   = true
}