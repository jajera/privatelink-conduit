variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-southeast-2"
}

variable "aws_profile" {
  description = "AWS CLI profile for the shared-services account"
  type        = string
  default     = "shared-services"
}

variable "project_name" {
  description = "Name prefix for resources"
  type        = string
  default     = "plc"
}

variable "vpc_cidr" {
  description = "CIDR for the shared-services VPC"
  type        = string
  default     = "10.50.0.0/16"
}

variable "sandbox_account_id" {
  description = "AWS account ID allowed to create the PrivateLink interface endpoint"
  type        = string
}

variable "supported_regions" {
  description = "Regions allowed to create interface endpoints to this service (host Region must be included for cross-Region PrivateLink)"
  type        = list(string)
  default     = ["ap-southeast-2", "ap-southeast-4"]
}
