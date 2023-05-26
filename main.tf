data "aws_route53_zone" "pub" {
  name         = var.dns_zone
  private_zone = false
}


resource "aviatrix_segmentation_network_domain" "shared" {
  domain_name = "SHARED"
}

resource "aviatrix_segmentation_network_domain" "app1" {
  domain_name = "APP1"
}

resource "aviatrix_segmentation_network_domain" "app2" {
  domain_name = "APP2"
}

resource "aviatrix_segmentation_network_domain" "onprem" {
  domain_name = "ONPREM"
}

# Create an Aviatrix Segmentation Network Domain
resource "aviatrix_segmentation_network_domain_connection_policy" "shared1" {
  domain_name_1 = aviatrix_segmentation_network_domain.shared.domain_name
  domain_name_2 = aviatrix_segmentation_network_domain.app1.domain_name
}

resource "aviatrix_segmentation_network_domain_connection_policy" "shared2" {
  domain_name_1 = aviatrix_segmentation_network_domain.shared.domain_name
  domain_name_2 = aviatrix_segmentation_network_domain.app2.domain_name
}


resource "aviatrix_distributed_firewalling_config" "default" {
  enable_distributed_firewalling = true
}

variable "smartgroup_any" {
  default = "def000ad-0000-0000-0000-000000000000"
}

variable "smartgroup_internet" {
  default = "def000ad-0000-0000-0000-000000000001"
}

## AWS

module "aws_transit" {
  source              = "terraform-aviatrix-modules/mc-transit/aviatrix"
  cloud               = "AWS"
  version             = "2.4.2"
  account             = var.aws_account_name
  region              = var.aws_region
  cidr                = "10.40.250.0/23"
  name                = "aws-eu-trans"
  ha_gw               = false
  instance_size       = "t3.micro"
  enable_segmentation = true
}

module "shared-spoke" {
  source  = "terraform-aviatrix-modules/mc-spoke/aviatrix"
  cloud   = "AWS"
  version = "1.5.0"

  name           = "aws-shared"
  cidr           = "10.1.0.0/16"
  region         = var.aws_region
  account        = var.aws_account_name
  transit_gw     = module.aws_transit.transit_gateway.gw_name
  instance_size  = "t3.micro"
  ha_gw          = false
  network_domain = aviatrix_segmentation_network_domain.shared.domain_name
  single_ip_snat = true
}

module "app1-spoke" {
  source  = "terraform-aviatrix-modules/mc-spoke/aviatrix"
  cloud   = "AWS"
  version = "1.5.0"

  name           = "aws-app1"
  cidr           = "10.2.0.0/16"
  region         = var.aws_region
  account        = var.aws_account_name
  transit_gw     = module.aws_transit.transit_gateway.gw_name
  instance_size  = "t3.micro"
  ha_gw          = false
  network_domain = aviatrix_segmentation_network_domain.app1.domain_name
  single_ip_snat = true
}

module "app2-spoke" {
  source  = "terraform-aviatrix-modules/mc-spoke/aviatrix"
  cloud   = "AWS"
  version = "1.5.0"

  name           = "aws-app2"
  cidr           = "10.3.0.0/16"
  region         = var.aws_region
  account        = var.aws_account_name
  transit_gw     = module.aws_transit.transit_gateway.gw_name
  instance_size  = "t3.micro"
  ha_gw          = false
  network_domain = aviatrix_segmentation_network_domain.app2.domain_name
  single_ip_snat = true
}

# Guacamole
module "guac" {
  source    = "git::https://github.com/fkhademi/terraform-aws-instance-module.git?ref=ubuntu-20"
  name      = "guac-vm"
  region    = var.aws_region
  vpc_id    = module.shared-spoke.vpc.vpc_id
  subnet_id = module.shared-spoke.vpc.public_subnets[1].subnet_id
  ssh_key   = var.ssh_key
  user_data = templatefile("${path.module}/cloud-init.tpl",
    {
      username   = "demo"
      password   = "Password123!"
      hostname   = "guac.${var.dns_zone}"
      domainname = var.dns_zone
      host1      = module.app1-dev.vm.private_ip
      host2      = module.app1-prod.vm.private_ip
      host3      = module.app2-dev.vm.private_ip
      host4      = module.app2-prod.vm.private_ip
  })
  public_ip      = true
  instance_size  = "t3.small"
  ubuntu_version = 18
}

resource "aws_route53_record" "guac" {
  zone_id = data.aws_route53_zone.pub.zone_id
  name    = "guac.${data.aws_route53_zone.pub.name}"
  type    = "A"
  ttl     = "1"
  records = [module.guac.vm.public_ip]
}

resource "aviatrix_smart_group" "guac" {
  name = "GUACAMOLE"
  selector {
    match_expressions {
      type         = "vm"
      account_name = var.aws_account_name
      region       = var.aws_region
      tags = {
        Name = "guac-vm-srv"
      }
    }
  }
}

resource "aviatrix_distributed_firewalling_policy_list" "guac" {
  policies {
    name     = "GUAC-REMOTEACCESS"
    action   = "PERMIT"
    priority = 1
    protocol = "TCP"
    logging  = true
    watch    = false
    src_smart_groups = [
      aviatrix_smart_group.guac.uuid
    ]
    dst_smart_groups = [
      aviatrix_smart_group.app1-dev.uuid,
      aviatrix_smart_group.app1-prod.uuid,
      aviatrix_smart_group.app2-dev.uuid,
      aviatrix_smart_group.app2-prod.uuid
    ]
  }

  policies {
    name     = "DENY-ALL"
    action   = "DENY"
    priority = 20000000
    protocol = "ANY"
    logging  = true
    watch    = false
    src_smart_groups = [
      var.smartgroup_any
    ]
    dst_smart_groups = [
      var.smartgroup_any
    ]
  }

}

# APP1 Dev
module "app1-dev" {
  source    = "git::https://github.com/fkhademi/terraform-aws-instance-module.git"
  name      = "app1-dev"
  region    = var.aws_region
  vpc_id    = module.app1-spoke.vpc.vpc_id
  subnet_id = module.app1-spoke.vpc.private_subnets[0].subnet_id
  ssh_key   = var.ssh_key
  user_data = templatefile("${path.module}/egress.sh",
    {
      username = "demo"
      password = "Password123!"
      hostname = "app1-dev"
    }
  )
}

resource "aws_route53_record" "app1-dev" {
  zone_id = data.aws_route53_zone.pub.zone_id
  name    = "app1-dev.${data.aws_route53_zone.pub.name}"
  type    = "A"
  ttl     = "1"
  records = [module.app1-dev.vm.private_ip]
}

# Create an Aviatrix Smart Group
resource "aviatrix_smart_group" "app1-dev" {
  name = "APP1-DEV"
  selector {
    match_expressions {
      type         = "vm"
      account_name = var.aws_account_name
      region       = var.aws_region
      tags = {
        Name = "app1-dev-srv"
      }
    }
  }
}

# APP1 Prod
module "app1-prod" {
  source    = "git::https://github.com/fkhademi/terraform-aws-instance-module.git"
  name      = "app1-prod"
  region    = var.aws_region
  vpc_id    = module.app1-spoke.vpc.vpc_id
  subnet_id = module.app1-spoke.vpc.private_subnets[0].subnet_id
  ssh_key   = var.ssh_key
  user_data = templatefile("${path.module}/egress.sh",
    {
      username = "demo"
      password = "Password123!"
      hostname = "app1-prod"
    }
  )
}

resource "aws_route53_record" "app1-prod" {
  zone_id = data.aws_route53_zone.pub.zone_id
  name    = "app1-prod.${data.aws_route53_zone.pub.name}"
  type    = "A"
  ttl     = "1"
  records = [module.app1-prod.vm.private_ip]
}

resource "aviatrix_smart_group" "app1-prod" {
  name = "APP1-PROD"
  selector {
    match_expressions {
      type         = "vm"
      account_name = var.aws_account_name
      region       = var.aws_region
      tags = {
        Name = "app1-prod-srv"
      }
    }
  }
}

## SPOKE2

# APP2 Dev
module "app2-dev" {
  source    = "git::https://github.com/fkhademi/terraform-aws-instance-module.git"
  name      = "app2-dev"
  region    = var.aws_region
  vpc_id    = module.app2-spoke.vpc.vpc_id
  subnet_id = module.app2-spoke.vpc.private_subnets[0].subnet_id
  ssh_key   = var.ssh_key
  user_data = templatefile("${path.module}/egress.sh",
    {
      username = "demo"
      password = "Password123!"
      hostname = "app2-dev"
    }
  )
}

resource "aws_route53_record" "app2-dev" {
  zone_id = data.aws_route53_zone.pub.zone_id
  name    = "app2-dev.${data.aws_route53_zone.pub.name}"
  type    = "A"
  ttl     = "1"
  records = [module.app2-dev.vm.private_ip]
}

resource "aviatrix_smart_group" "app2-dev" {
  name = "APP2-DEV"
  selector {
    match_expressions {
      type         = "vm"
      account_name = var.aws_account_name
      region       = var.aws_region
      tags = {
        Name = "app2-dev-srv"
      }
    }
  }
}

# APP1 Prod
module "app2-prod" {
  source    = "git::https://github.com/fkhademi/terraform-aws-instance-module.git"
  name      = "app2-prod"
  region    = var.aws_region
  vpc_id    = module.app2-spoke.vpc.vpc_id
  subnet_id = module.app2-spoke.vpc.private_subnets[0].subnet_id
  ssh_key   = var.ssh_key
  user_data = templatefile("${path.module}/egress.sh",
    {
      username = "demo"
      password = "Password123!"
      hostname = "app2-prod"
    }
  )
}

resource "aws_route53_record" "app2-prod" {
  zone_id = data.aws_route53_zone.pub.zone_id
  name    = "app2-prod.${data.aws_route53_zone.pub.name}"
  type    = "A"
  ttl     = "1"
  records = [module.app2-prod.vm.private_ip]
}

resource "aviatrix_smart_group" "app2-prod" {
  name = "APP2-PROD"
  selector {
    match_expressions {
      type         = "vm"
      account_name = var.aws_account_name
      region       = var.aws_region
      tags = {
        Name = "app2-prod-srv"
      }
    }
  }
}

# resource "guacamole_connection_ssh" "aws_int" {
#   count             = 4
#   name              = "int${count.index}-ssh"
#   parent_identifier = "ROOT"

#   parameters {
#     hostname = module.aws_int_srv[count.index].vm.private_ip
#     username = "demo"
#     password = "Password123!"
#     port     = 22
#   }
# }

# data "guacamole_user" "user" {
#   username = "guacadmin"
# }


# data "aws_ami" "guacamole" {
#   most_recent = true

#   filter {
#     name   = "owner-id"
#     values = ["679593333241"]
#   }

#   filter {
#     name   = "name"
#     values = ["bitnami-guacamole-1.4.0-73-r42*-x86_64-hvm-ebs*"]
#   }
# }

# module "ec2_instance_guacamole" {
#   source = "terraform-aws-modules/ec2-instance/aws"

#   name = "guacamole-01"

#   ami                         = data.aws_ami.guacamole.image_id
#   instance_type               = "t3a.small"
#   key_name                    = "guac-vm-key"
#   monitoring                  = true
#   vpc_security_group_ids      = []
#   subnet_id                   = module.aws_int_spoke[0].vpc.public_subnets[1].subnet_id
#   associate_public_ip_address = true

#   tags = {
#     Cloud       = "AWS"
#     Application = "Jump Server"
#   }
# }


# module "aws_dev_spoke" {
#   count   = 2
#   source  = "terraform-aviatrix-modules/mc-spoke/aviatrix"
#   cloud   = "AWS"
#   version = "1.5.0"

#   name           = "aws-dev${count.index}"
#   cidr           = "10.40.1${count.index}.0/24"
#   region         = var.aws_region
#   account        = var.aws_account_name
#   transit_gw     = module.aws_transit.transit_gateway.gw_name
#   instance_size  = "t3.micro"
#   ha_gw          = false
#   network_domain = "Development"
# }

# module "aws_test_spoke" {
#   count   = 2
#   source  = "terraform-aviatrix-modules/mc-spoke/aviatrix"
#   cloud   = "AWS"
#   version = "1.5.0"

#   name           = "aws-test${count.index}"
#   cidr           = "10.40.2${count.index}.0/24"
#   region         = var.aws_region
#   account        = var.aws_account_name
#   transit_gw     = module.aws_transit.transit_gateway.gw_name
#   instance_size  = "t3.micro"
#   ha_gw          = false
#   network_domain = "Test"
# }

# module "aws_shared_spoke" {
#   count   = 1
#   source  = "terraform-aviatrix-modules/mc-spoke/aviatrix"
#   cloud   = "AWS"
#   version = "1.5.0"

#   name           = "aws-shared${count.index}"
#   cidr           = "10.40.3${count.index}.0/24"
#   region         = var.aws_region
#   account        = var.aws_account_name
#   transit_gw     = module.aws_transit.transit_gateway.gw_name
#   instance_size  = "t3.micro"
#   ha_gw          = false
#   network_domain = "Shared"
# }

# # AWS US

# module "aws_transit_us" {
#   source              = "terraform-aviatrix-modules/mc-transit/aviatrix"
#   cloud               = "AWS"
#   version             = "2.2.1"
#   account             = var.aws_account_name
#   region              = "us-east-1"
#   cidr                = "10.41.250.0/23"
#   name                = "aws-us-trans"
#   ha_gw               = false
#   instance_size       = "t3.micro"
#   enable_segmentation = true
# }

# module "aws_prod_spoke_us" {
#   count   = 1
#   source  = "terraform-aviatrix-modules/mc-spoke/aviatrix"
#   cloud   = "AWS"
#   version = "1.5.0"

#   name           = "aws-prod-us${count.index}"
#   cidr           = "10.41.${count.index}.0/24"
#   region         = "us-east-1"
#   account        = var.aws_account_name
#   transit_gw     = module.aws_transit_us.transit_gateway.gw_name
#   instance_size  = "t3.micro"
#   ha_gw          = false
#   network_domain = "Production"
# }

# module "aws_dev_spoke_us" {
#   count   = 1
#   source  = "terraform-aviatrix-modules/mc-spoke/aviatrix"
#   cloud   = "AWS"
#   version = "1.5.0"

#   name           = "aws-dev-us${count.index}"
#   cidr           = "10.41.1${count.index}.0/24"
#   region         = "us-east-1"
#   account        = var.aws_account_name
#   transit_gw     = module.aws_transit_us.transit_gateway.gw_name
#   instance_size  = "t3.micro"
#   ha_gw          = false
#   network_domain = "Development"
# }

# module "aws_test_spoke_us" {
#   count   = 1
#   source  = "terraform-aviatrix-modules/mc-spoke/aviatrix"
#   cloud   = "AWS"
#   version = "1.5.0"

#   name           = "aws-test-us${count.index}"
#   cidr           = "10.41.2${count.index}.0/24"
#   region         = "us-east-1"
#   account        = var.aws_account_name
#   transit_gw     = module.aws_transit_us.transit_gateway.gw_name
#   instance_size  = "t3.micro"
#   ha_gw          = false
#   network_domain = "Test"
# }

# Azure

# module "azure_transit" {
#   source              = "terraform-aviatrix-modules/mc-transit/aviatrix"
#   cloud               = "Azure"
#   version             = "2.4.2"
#   account             = var.azure_account_name
#   region              = var.azure_region
#   cidr                = "10.50.250.0/23"
#   name                = "azure-trans"
#   ha_gw               = false
#   instance_size       = "Standard_B1ms"
#   enable_segmentation = true
# }

# module "azure_prod_spoke" {
#   count   = 1
#   source  = "terraform-aviatrix-modules/mc-spoke/aviatrix"
#   cloud   = "Azure"
#   version = "1.5.0"

#   name           = "azure-prod${count.index}"
#   cidr           = "10.50.${count.index}.0/24"
#   region         = var.azure_region
#   account        = var.azure_account_name
#   transit_gw     = module.azure_transit.transit_gateway.gw_name
#   instance_size  = "Standard_B1ms"
#   ha_gw          = false
#   network_domain = "Production"
# }

# module "azure_dev_spoke" {
#   count   = 1
#   source  = "terraform-aviatrix-modules/mc-spoke/aviatrix"
#   cloud   = "Azure"
#   version = "1.5.0"

#   name           = "azure-dev${count.index}"
#   cidr           = "10.50.1${count.index}.0/24"
#   region         = var.azure_region
#   account        = var.azure_account_name
#   transit_gw     = module.azure_transit.transit_gateway.gw_name
#   instance_size  = "Standard_B1ms"
#   ha_gw          = false
#   network_domain = "Development"
# }

# Azure Region 2


# module "azure_transit_de" {
#   source                 = "terraform-aviatrix-modules/mc-transit/aviatrix"
#   cloud                  = "Azure"
#   version                = "2.2.1"
#   account                = var.azure_account_name
#   region                 = "Germany West Central"
#   cidr                   = "10.60.250.0/23"
#   name                   = "azure-trans-de"
#   ha_gw                  = false
#   instance_size          = "Standard_B1ms"
# }

# module "azure_prod_spoke_de" {
#   count   = 1
#   source  = "terraform-aviatrix-modules/mc-spoke/aviatrix"
#   cloud   = "Azure"
#   version = "1.5.0"

#   name                             = "azure-prod-de${count.index}"
#   cidr                             = "10.60.${count.index}.0/24"
#   region                           = "Germany West Central"
#   account                          = var.azure_account_name
#   transit_gw                       = module.azure_transit_de.transit_gateway.gw_name
#   instance_size                    = "Standard_B1ms"
#   ha_gw                            = false
# }

# module "azure_dev_spoke_de" {
#   count   = 1
#   source  = "terraform-aviatrix-modules/mc-spoke/aviatrix"
#   cloud   = "Azure"
#   version = "1.5.0"

#   name                             = "azure-dev-de${count.index}"
#   cidr                             = "10.60.1${count.index}.0/24"
#   region                           = var.azure_region
#   account                          = var.azure_account_name
#   transit_gw                       = module.azure_transit_de.transit_gateway.gw_name
#   instance_size                    = "Standard_B1ms"
#   ha_gw                            = false
# }



## GCP

# module "gcp_transit" {
#   source              = "terraform-aviatrix-modules/mc-transit/aviatrix"
#   cloud               = "GCP"
#   version             = "2.2.1"
#   account             = var.gcp_account_name
#   region              = var.gcp_region
#   cidr                = "10.150.250.0/23"
#   name                = "gcp-trans"
#   ha_gw               = false
#   instance_size       = "n1-standard-1"
#   enable_segmentation = true
# }

# module "gcp_prod_spoke" {
#   count   = 1
#   source  = "terraform-aviatrix-modules/mc-spoke/aviatrix"
#   cloud   = "GCP"
#   version = "1.5.0"

#   name           = "gcp-prod${count.index}"
#   cidr           = "10.150.${count.index}.0/24"
#   region         = var.gcp_region
#   account        = var.gcp_account_name
#   transit_gw     = module.gcp_transit.transit_gateway.gw_name
#   instance_size  = "n1-standard-1"
#   ha_gw          = false
#   network_domain = "Production"
# }

# module "gcp_dev_spoke" {
#   count   = 1
#   source  = "terraform-aviatrix-modules/mc-spoke/aviatrix"
#   cloud   = "GCP"
#   version = "1.5.0"

#   name           = "gcp-dev${count.index}"
#   cidr           = "10.150.1${count.index}.0/24"
#   region         = var.gcp_region
#   account        = var.gcp_account_name
#   transit_gw     = module.gcp_transit.transit_gateway.gw_name
#   instance_size  = "n1-standard-1"
#   ha_gw          = false
#   network_domain = "Development"
# }

# Create an Aviatrix Gateway FQDN filter
# resource "aviatrix_fqdn" "fqdn_tag01" {
#   fqdn_tag     = "allow-list-prod"
#   fqdn_enabled = true
#   fqdn_mode    = "white"

#   domain_names {
#     fqdn  = "google.ca"
#     proto = "tcp"
#     port  = 443
#   }
# }
