packer {
  required_plugins {
    amazon = {
      version = ">= 1.0.0"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

data "amazon-ami" "ubuntu-focal-2004-amd64" {
  filters = {
    name                = "ubuntu/images/*ubuntu-focal-20.04-amd64-server-*"
    root-device-type    = "ebs"
    virtualization-type = "hvm"
  }
  most_recent = true
  owners      = ["099720109477"]
}

locals {
  timestamp      = regex_replace(timestamp(), "[- TZ:]", "")
  region         = "eu-west-1"
  aws_account_id = "999999999999"
  ami_users      = []
}

source "amazon-ebssurrogate" "ubuntu" {
  // # if you are building on sub-account through role
  // assume_role {
  //   role_arn = "arn:aws:iam::${local.aws_account_id}:role/OrganizationAccountAccessRole"
  // }
  region = local.region
  subnet_id = "subnet-04ba6eg5b40c2b034"

  ami_users       = local.ami_users
  ami_name        = "ubuntu-focal-base-ami-${local.timestamp}"
  ami_description = "Ubuntu 20.04 LTS Focal"

  source_ami              = data.amazon-ami.ubuntu-focal-2004-amd64.id
  ami_architecture        = "x86_64"
  ami_virtualization_type = "hvm"
  instance_type           = "t2.micro"

  launch_block_device_mappings {
    device_name           = "/dev/sda1"
    delete_on_termination = true
    omit_from_artifact    = true
    encrypted             = true
    volume_type           = "gp2"
    volume_size           = 8
  }

  launch_block_device_mappings {
    device_name           = "/dev/xvdf"
    delete_on_termination = true
    encrypted             = true
    volume_type           = "gp2"
    volume_size           = 2
  }

  ami_root_device {
    source_device_name    = "/dev/xvdf"
    device_name           = "/dev/sda1"
    delete_on_termination = true
    volume_type           = "gp2"
    volume_size           = 2
  }

  ena_support   = true
  sriov_support = true

  communicator = "ssh"
  ssh_username = "ubuntu"

  user_data_file = "cloud-init/50_users.cfg"
}

build {
  sources = ["source.amazon-ebssurrogate.ubuntu"]

  provisioner "shell" {
    execute_command  = "sudo -S sh -c '{{ .Vars }} {{ .Path }}'"
    environment_vars = ["DEBIAN_FRONTEND=noninteractive"]
    inline = [
      "sgdisk -n 14:2048:10239 -t 14:ef02 -c 14:grub /dev/xvdf",
      "sgdisk -n 15:10240:227327 -t 15:ef00 /dev/xvdf",
      "sgdisk -n 1:227328:0 /dev/xvdf",
      "mkfs.ext4 /dev/xvdf1",
      "mount /dev/xvdf1 /mnt/",
      "add-apt-repository universe",
      "apt-get update && apt-get install -y debootstrap arch-install-scripts",
      "debootstrap focal /mnt",
      "genfstab -U /mnt >> /mnt/etc/fstab",
      "cp /etc/apt/sources.list /mnt/etc/apt/sources.list",
      "arch-chroot /mnt apt-get update",
      "arch-chroot /mnt apt-get upgrade -y",
      "arch-chroot /mnt apt-get clean",
      "arch-chroot /mnt dpkg-reconfigure tzdata",
      "arch-chroot /mnt dpkg-reconfigure locales",
      "arch-chroot /mnt apt-get install -y --no-install-recommends cloud-init linux-aws initramfs-tools grub2-common grub-pc",
      "arch-chroot /mnt apt-get install -y ubuntu-server bash less apt ssh man patch iotop tcpstat sysstat",
      "arch-chroot /mnt apt-get clean",
      "cp /etc/default/grub.d/50-cloudimg-settings.cfg /mnt/etc/default/grub.d/",
      "arch-chroot /mnt grub-install --boot-directory=/boot /dev/xvdf",
      "arch-chroot /mnt update-grub"
    ]
  }
  provisioner "file" {
    source      = "cloud-init/50_users.cfg"
    destination = "/tmp/50_users.cfg"
  }
  provisioner "shell" {
    inline = [
      "sudo cp /tmp/50_users.cfg /mnt/etc/cloud/cloud.cfg.d/50_users.cfg",
      "sudo umount /mnt"
    ]
  }
}
