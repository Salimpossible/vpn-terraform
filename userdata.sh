#!/bin/bash

export DEBIAN_FRONTEND=noninteractive

# Update system packages
apt-get update -y
apt-get upgrade -y -o Dpkg::Options::="--force-confold"

# Install WireGuard, iptables, and fail2ban
apt-get install -y wireguard wireguard-tools iptables iptables-persistent fail2ban

# Enable IP forwarding — write to sysctl.d so it survives reboot and takes priority
cat > /etc/sysctl.d/99-ip-forward.conf <<EOF
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
EOF

# Apply immediately
sysctl -w net.ipv4.ip_forward=1
sysctl -w net.ipv6.conf.all.forwarding=1

# Verify (logged to cloud-init output)
sysctl net.ipv4.ip_forward >> /var/log/cloud-init-output.log

# Create WireGuard configuration
cat > /etc/wireguard/wg0.conf <<'WGCONF'
[Interface]
Address = 10.0.100.1/24
ListenPort = ${wg_server_port}
PrivateKey = ${wg_server_private_key}
PostUp = ETH=$(ip route | awk '/default/ {print $5; exit}'); iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o $ETH -j MASQUERADE; iptables -t nat -A PREROUTING -i $ETH -p tcp --dport 6881 -j DNAT --to-destination 10.0.100.2:6881; iptables -t nat -A PREROUTING -i $ETH -p udp --dport 6881 -j DNAT --to-destination 10.0.100.2:6881; ip6tables -A FORWARD -i wg0 -j ACCEPT; ip6tables -t nat -A POSTROUTING -o $ETH -j MASQUERADE
PostDown = ETH=$(ip route | awk '/default/ {print $5; exit}'); iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o $ETH -j MASQUERADE; iptables -t nat -D PREROUTING -i $ETH -p tcp --dport 6881 -j DNAT --to-destination 10.0.100.2:6881; iptables -t nat -D PREROUTING -i $ETH -p udp --dport 6881 -j DNAT --to-destination 10.0.100.2:6881; ip6tables -D FORWARD -i wg0 -j ACCEPT; ip6tables -t nat -D POSTROUTING -o $ETH -j MASQUERADE

[Peer]
PublicKey = ${wg_client_public_key}
AllowedIPs = ${wg_client_allowed_ip}
WGCONF

# Set strict permissions on WireGuard config
chmod 600 /etc/wireguard/wg0.conf

# Enable and start WireGuard
systemctl enable wg-quick@wg0
systemctl start wg-quick@wg0

# Harden SSH: disable password authentication
sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
systemctl restart sshd

# Configure fail2ban for SSH brute-force protection
cat > /etc/fail2ban/jail.local <<'F2BCONF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5

[sshd]
enabled = true
F2BCONF

systemctl enable fail2ban
systemctl start fail2ban

# Log completion
echo "WireGuard VPN server initialization completed successfully" >> /var/log/cloud-init-output.log
