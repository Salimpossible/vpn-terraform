resource "aws_security_group" "vpn" {
  name_prefix = "${var.project_name}-"
  description = "WireGuard VPN + restricted SSH security group"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name      = "${var.project_name}-sg"
    Project   = var.project_name
    ManagedBy = "terraform"
  }
}

resource "aws_vpc_security_group_ingress_rule" "wireguard_ipv4" {
  security_group_id = aws_security_group.vpn.id

  from_port   = var.wg_server_port
  to_port     = var.wg_server_port
  ip_protocol = "udp"
  cidr_ipv4   = "0.0.0.0/0"

  tags = {
    Name = "wireguard-ipv4"
  }
}

resource "aws_vpc_security_group_ingress_rule" "wireguard_ipv6" {
  security_group_id = aws_security_group.vpn.id

  from_port   = var.wg_server_port
  to_port     = var.wg_server_port
  ip_protocol = "udp"
  cidr_ipv6   = "::/0"

  tags = {
    Name = "wireguard-ipv6"
  }
}

resource "aws_vpc_security_group_ingress_rule" "ssh" {
  security_group_id = aws_security_group.vpn.id

  from_port   = 22
  to_port     = 22
  ip_protocol = "tcp"
  cidr_ipv4   = var.allowed_ssh_cidr

  tags = {
    Name = "ssh-restricted"
  }
}

resource "aws_vpc_security_group_ingress_rule" "qbittorrent_tcp" {
  security_group_id = aws_security_group.vpn.id

  from_port   = 6881
  to_port     = 6881
  ip_protocol = "tcp"
  cidr_ipv4   = "0.0.0.0/0"

  tags = {
    Name = "qbittorrent-tcp"
  }
}

resource "aws_vpc_security_group_ingress_rule" "qbittorrent_udp" {
  security_group_id = aws_security_group.vpn.id

  from_port   = 6881
  to_port     = 6881
  ip_protocol = "udp"
  cidr_ipv4   = "0.0.0.0/0"

  tags = {
    Name = "qbittorrent-udp"
  }
}

resource "aws_vpc_security_group_egress_rule" "all_outbound" {
  security_group_id = aws_security_group.vpn.id

  from_port   = -1
  to_port     = -1
  ip_protocol = "-1"
  cidr_ipv4   = "0.0.0.0/0"

  tags = {
    Name = "allow-all-egress"
  }
}

resource "aws_vpc_security_group_egress_rule" "all_outbound_ipv6" {
  security_group_id = aws_security_group.vpn.id

  from_port   = -1
  to_port     = -1
  ip_protocol = "-1"
  cidr_ipv6   = "::/0"

  tags = {
    Name = "allow-all-egress-ipv6"
  }
}
