output "endpoint_service_name" {
  description = "PrivateLink endpoint service name for the sandbox stack"
  value       = aws_vpc_endpoint_service.this.service_name
}

output "endpoint_service_region" {
  description = "Host Region of the endpoint service"
  value       = var.aws_region
}

output "supported_regions" {
  description = "Consumer Regions allowed for cross-Region PrivateLink"
  value       = aws_vpc_endpoint_service.this.supported_regions
}

output "app_private_ip" {
  description = "App EC2 private IP (sandbox has no route here)"
  value       = aws_instance.app.private_ip
}

output "rds_endpoint" {
  description = "RDS endpoint address (sandbox has no route here)"
  value       = aws_db_instance.this.address
}

output "vpc_id" {
  value = aws_vpc.this.id
}

output "nlb_dns_name" {
  value = aws_lb.nlb.dns_name
}
