variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-southeast-2"
}

variable "aws_profile" {
  description = "AWS CLI profile for the sandbox account"
  type        = string
  default     = "sandbox"
}

variable "project_name" {
  description = "Name prefix for resources"
  type        = string
  default     = "plc"
}

variable "vpc_cidr" {
  description = "CIDR for the sandbox VPC"
  type        = string
  default     = "10.51.0.0/16"
}

variable "endpoint_service_name" {
  description = "PrivateLink endpoint service name from shared-services output"
  type        = string
}
