variable "aws_region" {
  description = "AWS region for the cross-region sandbox consumer (Melbourne)"
  type        = string
  default     = "ap-southeast-4"
}

variable "aws_profile" {
  description = "AWS CLI profile for the sandbox account"
  type        = string
  default     = "sandbox"
}

variable "project_name" {
  description = "Name prefix for resources (IAM names are global)"
  type        = string
  default     = "plc-xr"
}

variable "vpc_cidr" {
  description = "CIDR for the cross-region sandbox VPC"
  type        = string
  default     = "10.61.0.0/16"
}

variable "endpoint_service_name" {
  description = "PrivateLink endpoint service name from shared-services (Sydney) output"
  type        = string
}

variable "endpoint_service_region" {
  description = "Region where the endpoint service is hosted (Sydney)"
  type        = string
  default     = "ap-southeast-2"
}
