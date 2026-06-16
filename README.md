# WireGuard VPN on AWS Free Tier

Deploy a privacy-conscious WireGuard VPN server on AWS EC2 (t3.micro) using Terraform. Fully reproducible, EU-based, and within free tier limits.

## ✅ Prerequisites

- **Terraform** ≥ 1.5.0 ([download](https://www.terraform.io/downloads))
- **AWS account** with free tier eligibility (12 months)
- **AWS CLI** configured with credentials (`aws configure`)
- **WireGuard tools** on your local client machine
  - Ubuntu/Debian: `sudo apt install wireguard`
  - macOS: `brew install wireguard-tools`
  - Windows: [WireGuard installer](https://www.wireguard.com/install/)
- **SSH key pair** (default: `~/.ssh/id_ed25519.pub`)
  - If you don't have one: `ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519`

## 🔑 Generate WireGuard Keys

Before running Terraform, generate WireGuard keys locally (do NOT let Terraform generate them — keys in state files are a privacy risk).

```bash
# Generate server keys
wg genkey | tee server_private.key | wg pubkey > server_public.key

# Generate client keys
wg genkey | tee client_private.key | wg pubkey > client_public.key

# Display keys for copying into terraform.tfvars
echo "=== Server Private Key ==="
cat server_private.key
echo "=== Client Public Key ==="
cat client_public.key
```

Store these files somewhere safe (not in the Terraform directory, not in git).

## 📝 Create terraform.tfvars

Copy the example file and fill in your values:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:

```hcl
allowed_ssh_cidr           = "YOUR_IP/32"              # Replace with your public IP from: curl https://ifconfig.me
aws_region                 = "eu-west-3"              # Paris (EU jurisdiction, best for privacy)
wg_server_private_key      = "PASTE_SERVER_PRIVATE_KEY"  # From server_private.key
wg_client_public_key       = "PASTE_CLIENT_PUBLIC_KEY"   # From client_public.key
ssh_public_key_path        = "~/.ssh/id_ed25519.pub"     # Your SSH public key
```

**⚠️ Important**: Never commit `terraform.tfvars` to git. It contains sensitive keys.

## 🚀 Deploy

Initialize and apply Terraform:

```bash
terraform init
terraform plan    # Review what will be created
terraform apply   # Deploy to AWS
```

When prompted, review the plan and type `yes` to confirm.

### Output

After successful apply, Terraform will print:

```
Outputs:

ssh_command = "ssh -i ~/.ssh/id_ed25519 ubuntu@52.123.45.67"
vpn_instance_id = "i-0abcd1234efgh5678"
vpn_public_ip = "52.123.45.67"
wg_client_endpoint = "52.123.45.67:51820"
```

Save these values — you'll need them for the client config.

## 💻 Client Configuration

Create a WireGuard client config file on your local machine.

**File location:**
- Linux/macOS: `~/.config/wireguard/wg-vpn.conf`
- Windows: `C:\Program Files\WireGuard\Data\Configurations\wg-vpn.conf`

**Content** (replace placeholders from Terraform output):

```ini
[Interface]
PrivateKey = <PASTE_CLIENT_PRIVATE_KEY>
Address = 10.0.100.2/32
DNS = 1.1.1.1, 1.0.0.1

[Peer]
PublicKey = <PASTE_SERVER_PUBLIC_KEY>
Endpoint = <vpn_public_ip>:51820
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
```

Where:
- `<PASTE_CLIENT_PRIVATE_KEY>` = contents of `client_private.key`
- `<PASTE_SERVER_PUBLIC_KEY>` = contents of `server_public.key` 
- `<vpn_public_ip>` = output `vpn_public_ip` from Terraform

## 🔌 Connect to VPN

### Linux/macOS

```bash
sudo wg-quick up wg-vpn
# Verify: sudo wg show
# Disconnect: sudo wg-quick down wg-vpn
```

### Windows

Use the WireGuard GUI application:
1. Open WireGuard
2. Import the config file
3. Click "Activate"

## ✔️ Verify Connection

Check that your traffic is routed through the AWS instance:

```bash
curl https://ifconfig.me
# Should return the Elastic IP from Terraform output
```

Check latency to VPN server:

```bash
ping -c 5 $(terraform output -raw vpn_public_ip)
```

## 🔐 SSH Access

Connect to the VPN server for troubleshooting:

```bash
# Use the SSH command from Terraform output
ssh -i ~/.ssh/id_ed25519 ubuntu@<vpn_public_ip>

# Verify WireGuard status
sudo wg show
sudo systemctl status wg-quick@wg0

# View logs
sudo journalctl -u wg-quick@wg0 -f
```

## 📊 AWS Free Tier Limits

- **EC2**: 750 hours/month t3.micro (≈30 days 24/7)
- **Elastic IP**: Free while attached to running instance
- **Data transfer**: 100 GB outbound/month free
- **EBS storage**: 30 GB/month free (we use 8 GB encrypted volume)

Running 24/7: ~730 hours/month ✓ (stays within limits)

## 🔄 Migrate to S3 Backend (Optional)

For team projects or multiple machines, use S3 for remote state:

1. **Create S3 bucket** (in same region):
   ```bash
   aws s3api create-bucket \
     --bucket my-terraform-state-<unique> \
     --region eu-west-3 \
     --create-bucket-configuration LocationConstraint=eu-west-3
   ```

2. **Create `backend.tf`**:
   ```hcl
   terraform {
     backend "s3" {
       bucket         = "my-terraform-state-<unique>"
       key            = "wg-vpn/terraform.tfstate"
       region         = "eu-west-3"
       encrypt        = true
       dynamodb_table = "terraform-locks"
     }
   }
   ```

3. **Migrate state**:
   ```bash
   terraform init  # Terraform will prompt to migrate local state to S3
   ```

4. **Add DynamoDB lock table** (optional, for concurrency):
   ```hcl
   resource "aws_dynamodb_table" "terraform_locks" {
     name           = "terraform-locks"
     billing_mode   = "PAY_PER_REQUEST"
     hash_key       = "LockID"
     
     attribute {
       name = "LockID"
       type = "S"
     }
   }
   ```

## 🗑️ Tear Down

Destroy all AWS resources:

```bash
terraform destroy
# Review the destruction plan
# Type 'yes' to confirm
```

This will:
- Terminate the EC2 instance
- Release the Elastic IP
- Delete the VPC and subnets
- Remove security groups

**Important**: After destroying, manually delete the SSH key pair from AWS if you want to fully clean up:
```bash
aws ec2 delete-key-pair --key-name wg-vpn-key --region eu-west-3
```

## 🐛 Troubleshooting

### Cannot connect to SSH
- Check `allowed_ssh_cidr` in `terraform.tfvars` matches your current IP
- Instance security group only allows SSH from this CIDR
- Verify your IP: `curl https://ifconfig.me`

### WireGuard not running
```bash
# SSH into server, then:
sudo systemctl status wg-quick@wg0
sudo journalctl -u wg-quick@wg0 -n 20
sudo wg show
```

### No internet through VPN
- Verify IP forwarding: `cat /proc/sys/net/ipv4/ip_forward` (should be 1)
- Check iptables rules: `sudo iptables -t nat -L -n`
- Verify client can ping server: `ping 10.0.100.1` (from WireGuard tunnel IP)

### Terraform "public key must be a valid SSH public key"
- Ensure `ssh_public_key_path` points to a valid SSH public key file (not private key)
- Check key format: `cat ~/.ssh/id_ed25519.pub` (should start with `ssh-ed25519`)

## 📚 Region Options

Default is `eu-west-3` (Paris). Other free-tier regions:

| Region | Code | Privacy | Latency from Paris |
|--------|------|---------|-------------------|
| **Paris** | `eu-west-3` | ✅ EU/GDPR | Optimal |
| Frankfurt | `eu-central-1` | ✅ EU/GDPR | +5ms |
| Stockholm | `eu-north-1` | ✅ EU/GDPR/Strong | +30ms |
| São Paulo | `sa-east-1` | ✅ Non-Five Eyes | ~250ms |

Change region in `terraform.tfvars`:
```hcl
aws_region = "eu-central-1"
```

## 🔗 References

- [WireGuard Official](https://www.wireguard.com)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [AWS Free Tier](https://aws.amazon.com/free/)
- [WireGuard Configuration Guide](https://www.wireguard.com/quickstart/)
