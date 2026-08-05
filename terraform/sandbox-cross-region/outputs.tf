output "test_ec2_instance_id" {
  description = "SSM target for curl proof"
  value       = aws_instance.test.id
}

output "conduit_dns_name" {
  description = "Private DNS name for the cross-Region config API"
  value       = aws_route53_record.config.fqdn
}

output "endpoint_dns_name" {
  description = "Raw VPC endpoint DNS name"
  value       = aws_vpc_endpoint.conduit.dns_entry[0].dns_name
}

output "endpoint_service_region" {
  description = "Host Region of the endpoint service this consumer connects to"
  value       = var.endpoint_service_region
}

output "vpc_id" {
  value = aws_vpc.this.id
}
