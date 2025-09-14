output "load_balancer_dns_name" {
  description = "El nombre DNS del balanceador de carga"
  value       = aws_lb.load_balancer_agro.dns_name
}