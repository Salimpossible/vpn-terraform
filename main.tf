provider "aws" {
  profile = "terraform"
  region  = var.aws_region
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

resource "aws_key_pair" "vpn" {
  key_name   = "${var.project_name}-key"
  public_key = file(var.ssh_public_key_path)

  tags = {
    Name      = "${var.project_name}-key"
    Project   = var.project_name
    ManagedBy = "terraform"
  }
}

resource "aws_instance" "vpn" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.vpn.key_name
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.vpn.id]

  associate_public_ip_address = false

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 8
    delete_on_termination = true
    encrypted             = true

    tags = {
      Name      = "${var.project_name}-root-volume"
      Project   = var.project_name
      ManagedBy = "terraform"
    }
  }

  user_data = base64encode(templatefile("${path.module}/userdata.sh", {
    wg_server_private_key = var.wg_server_private_key
    wg_client_public_key  = var.wg_client_public_key
    wg_server_port        = var.wg_server_port
    wg_client_allowed_ip  = var.wg_client_allowed_ip
  }))

  tags = {
    Name      = "${var.project_name}-instance"
    Project   = var.project_name
    ManagedBy = "terraform"
  }

  depends_on = [
    aws_internet_gateway.main,
    aws_route_table_association.public
  ]
}

resource "aws_eip" "vpn" {
  instance = aws_instance.vpn.id
  domain   = "vpc"

  tags = {
    Name      = "${var.project_name}-eip"
    Project   = var.project_name
    ManagedBy = "terraform"
  }

  depends_on = [aws_internet_gateway.main]
}
