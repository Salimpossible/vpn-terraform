output "ssh_command" {
  description = "SSH command to connect to the VPN server"
  value       = "ssh -i ~/.ssh/id_ed25519 ubuntu@${aws_eip.vpn.public_ip}"
}

output "vpn_instance_id" {
  description = "EC2 instance ID of the WireGuard VPN server"
  value       = aws_instance.vpn.id
}

output "vpn_public_ip" {
  description = "Elastic IP address of the WireGuard VPN server"
  value       = aws_eip.vpn.public_ip
}

output "wg_client_endpoint" {
  description = "WireGuard client endpoint (paste into client config)"
  value       = "${aws_eip.vpn.public_ip}:${var.wg_server_port}"
}
