# Agent Prompt: Deploy a WireGuard VPN on AWS Free Tier with Terraform

## Objective

Create a complete, ready-to-apply Terraform project that deploys a WireGuard VPN server on AWS Free Tier using an Ubuntu 22.04 EC2 instance. The project must be fully reproducible and privacy-conscious.

---

## User Context

- Experienced DevOps engineer familiar with Terraform, Kubernetes, WireGuard, and Linux
- Prefers Ubuntu (22.04 LTS)
- Wants privacy (avoid US regions — prefer EU or non-Five Eyes jurisdiction)
- Must stay within AWS Free Tier (12 months from account creation)
- Will use this as a personal VPN (torrenting + general privacy), not a corporate VPN

---

## Target Architecture

```
[Client Device]
     │  WireGuard UDP 51820
     ▼
[AWS EC2 t3.micro — Ubuntu 22.04]
     │  Elastic IP (static)
     │  Security Group: UDP 51820 open, SSH 22 restricted to your IP
     │  ip_forward=1 + iptables NAT masquerade
     │  WireGuard wg0 interface
     ▼
[Internet]
```

---

## Terraform Project Structure to Generate

```
wireguard-aws/
├── main.tf           # EC2 instance, Elastic IP, association
├── vpc.tf            # VPC, subnet, IGW, route table (dedicated, not default VPC)
├── security.tf       # Security group rules
├── variables.tf      # Input variables with defaults
├── outputs.tf        # Elastic IP, instance ID, SSH command
├── userdata.sh       # WireGuard bootstrap script (runs on first boot)
└── README.md         # How to apply, connect, and tear down
```

---

## Detailed Requirements per File

### `variables.tf`

Define the following variables with sensible defaults:

| Variable | Default | Description |
|---|---|---|
| `aws_region` | `"eu-west-3"` | Paris — EU jurisdiction, low latency from France, not Five Eyes |
| `instance_type` | `"t3.micro"` | Free tier eligible (post July 2025) |
| `ami_id` | (computed) | Ubuntu 22.04 LTS — use a `data` source to fetch the latest AMI dynamically |
| `allowed_ssh_cidr` | `""` | Your IP in CIDR form (e.g. `"x.x.x.x/32"`). Required, no default. |
| `wg_server_port` | `51820` | WireGuard UDP port |
| `wg_server_private_key` | `""` | Pre-generated WireGuard server private key. Sensitive. Required. |
| `wg_client_public_key` | `""` | Client's WireGuard public key. Required. |
| `wg_client_allowed_ip` | `"10.0.100.2/32"` | Client tunnel IP |
| `project_name` | `"wg-vpn"` | Used as prefix for all resource names and tags |

> Note: For `wg_server_private_key` and `wg_client_public_key`, add instructions in README on how to generate them with `wg genkey | tee privatekey | wg pubkey > publickey`.

### `vpc.tf`

- Create a **dedicated VPC** (do not use the default VPC — better hygiene)
- CIDR: `10.0.0.0/16`
- One **public subnet**: `10.0.1.0/24`
- Internet Gateway attached to VPC
- Route table with `0.0.0.0/0 → IGW`
- Route table association to the public subnet
- Tag all resources with `Project = var.project_name`

### `security.tf`

Create a Security Group with:
- **Ingress**: UDP port `var.wg_server_port` from `0.0.0.0/0` and `::/0` (IPv4 + IPv6)
- **Ingress**: TCP port 22 from `var.allowed_ssh_cidr` only (never `0.0.0.0/0`)
- **Egress**: All traffic allowed
- Description: "WireGuard VPN + restricted SSH"

### `main.tf`

- `data "aws_ami"` source to get latest Ubuntu 22.04 LTS x86_64 AMI dynamically (owner `099720109477` = Canonical)
- `aws_key_pair` resource OR document in README that user must create a key pair manually in the console and pass its name as a variable
- `aws_instance` with:
  - `ami = data.aws_ami.ubuntu.id`
  - `instance_type = var.instance_type`
  - `subnet_id`, `vpc_security_group_ids`
  - `user_data = base64encode(templatefile("${path.module}/userdata.sh", { ... }))`  — pass WireGuard keys and config as template variables
  - `associate_public_ip_address = false` (we use Elastic IP instead)
  - Root volume: 8GB `gp3`, encrypted
  - Tags with `Name`, `Project`
- `aws_eip` resource (one Elastic IP)
- `aws_eip_association` to bind EIP to the instance

### `userdata.sh`

This script runs on first boot as root via `cloud-init`. It must:

1. `apt update && apt upgrade -y`
2. `apt install -y wireguard iptables`
3. Enable IP forwarding:
   ```bash
   echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
   echo "net.ipv6.conf.all.forwarding=1" >> /etc/sysctl.conf
   sysctl -p
   ```
4. Write `/etc/wireguard/wg0.conf` using template variables:
   ```ini
   [Interface]
   Address = 10.0.100.1/24
   ListenPort = ${wg_server_port}
   PrivateKey = ${wg_server_private_key}
   PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
   PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

   [Peer]
   PublicKey = ${wg_client_public_key}
   AllowedIPs = ${wg_client_allowed_ip}
   ```
5. Set permissions: `chmod 600 /etc/wireguard/wg0.conf`
6. Enable and start WireGuard: `systemctl enable wg-quick@wg0 && systemctl start wg-quick@wg0`
7. Install `fail2ban` for SSH brute-force protection
8. Disable SSH password auth: `sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config && systemctl restart sshd`

### `outputs.tf`

Output:
- `vpn_public_ip` — the Elastic IP address
- `ssh_command` — formatted SSH command: `ssh -i <key>.pem ubuntu@<elastic_ip>`
- `wg_client_endpoint` — `<elastic_ip>:<wg_server_port>` (ready to paste into client config)

### `README.md`

Must include:

1. **Prerequisites**: Terraform ≥ 1.5, AWS CLI configured, WireGuard installed on client
2. **Key generation** (run locally before `terraform apply`):
   ```bash
   wg genkey | tee server_private.key | wg pubkey > server_public.key
   wg genkey | tee client_private.key | wg pubkey > client_public.key
   ```
3. **`terraform.tfvars` example** (with all required values, sensitive keys as placeholders)
4. **Apply steps**: `terraform init`, `terraform plan`, `terraform apply`
5. **Client config** template to create on the client machine:
   ```ini
   [Interface]
   PrivateKey = <client_private_key>
   Address = 10.0.100.2/32
   DNS = 1.1.1.1

   [Peer]
   PublicKey = <server_public_key>
   Endpoint = <vpn_public_ip>:51820
   AllowedIPs = 0.0.0.0/0, ::/0
   PersistentKeepalive = 25
   ```
6. **Verify connection**: `curl https://ifconfig.me` should return the AWS Elastic IP
7. **Tear down**: `terraform destroy`
8. **Free tier limits reminder**: 750 hours/month EC2 + 100GB outbound data/month free. Keep the instance running 24/7 — one t3.micro = ~730h/month, stays within limits.

---

## Constraints & Best Practices

- **No hardcoded secrets** in `.tf` files — all sensitive values via `variables.tf` with `sensitive = true`
- Add `.gitignore` with: `*.tfvars`, `*.tfstate`, `*.tfstate.backup`, `.terraform/`, `*.key`
- Use `terraform.tfvars` for secrets, never commit it
- All resources must have consistent `tags` block: `{ Project = var.project_name, ManagedBy = "terraform" }`
- Use `required_providers` block with pinned AWS provider version (`~> 5.0`)
- Use `required_version = ">= 1.5.0"` in `terraform` block
- The `userdata.sh` must be a `templatefile()` — never inline bash in HCL heredoc
- No use of `aws_default_vpc` — always create a dedicated VPC

---

## Region Recommendation Logic (document in README)

The default is `eu-west-3` (Paris) because:
- EU jurisdiction (GDPR applies, no bulk surveillance like Five Eyes)
- Lowest latency from France (~5ms)
- Free tier eligible

Other options to mention:
| Region | Code | Notes |
|---|---|---|
| Paris | `eu-west-3` | **Default — best for this user** |
| Frankfurt | `eu-central-1` | Slightly higher latency from Paris, German jurisdiction |
| Stockholm | `eu-north-1` | Swedish jurisdiction, strong privacy laws |
| São Paulo | `sa-east-1` | Non-Five Eyes, higher latency |

---

## Deliverable

Generate all files fully — no placeholders, no "TODO" comments. Every file must be complete and ready to use. The user should be able to run `terraform init && terraform apply` after filling in `terraform.tfvars`.
