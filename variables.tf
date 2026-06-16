variable "allowed_ssh_cidr" {
  description = "CIDR block allowed to connect via SSH (e.g., your IP in /32 format)"
  type        = string
  sensitive   = false

  validation {
    condition     = can(cidrhost(var.allowed_ssh_cidr, 0))
    error_message = "allowed_ssh_cidr must be a valid CIDR block (e.g., 203.0.113.42/32)"
  }
}

variable "aws_region" {
  description = "AWS region for deployment (default: Paris/eu-west-3 for privacy)"
  type        = string
  default     = "eu-west-3"
}

variable "instance_type" {
  description = "EC2 instance type (default: t3.micro for free tier)"
  type        = string
  default     = "t3.micro"
}

variable "project_name" {
  description = "Project name used for tagging all resources"
  type        = string
  default     = "wg-vpn"
}

variable "ssh_public_key_path" {
  description = "Path to SSH public key file (will be read from local filesystem)"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "wg_client_allowed_ip" {
  description = "WireGuard client tunnel IP in CIDR format (e.g., 10.0.100.2/32)"
  type        = string
  default     = "10.0.100.2/32"
}

variable "wg_client_public_key" {
  description = "WireGuard client public key (generate with: wg genkey | tee client_private.key | wg pubkey > client_public.key)"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.wg_client_public_key) == 44 && can(regex("^[A-Za-z0-9+/]+=*$", var.wg_client_public_key))
    error_message = "wg_client_public_key must be a valid base64-encoded WireGuard public key (44 characters)"
  }
}

variable "wg_server_port" {
  description = "WireGuard server UDP port"
  type        = number
  default     = 51820

  validation {
    condition     = var.wg_server_port > 0 && var.wg_server_port <= 65535
    error_message = "wg_server_port must be between 1 and 65535"
  }
}

variable "wg_server_private_key" {
  description = "WireGuard server private key (generate with: wg genkey > server_private.key)"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.wg_server_private_key) == 44 && can(regex("^[A-Za-z0-9+/]+=*$", var.wg_server_private_key))
    error_message = "wg_server_private_key must be a valid base64-encoded WireGuard private key (44 characters)"
  }
}
