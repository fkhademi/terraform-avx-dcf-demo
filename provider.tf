provider "aviatrix" {
  controller_ip = var.controller_ip
  username      = var.username
  password      = var.password
  #version 	= "2.21.2"
  skip_version_validation = true
}

provider "aws" {
  region = var.aws_region
}

provider "azurerm" {
  features {}
}

provider "guacamole" {
  url                      = "http://guac.avxlab.de"
  username                 = "guacadmin"
  password                 = "guacadmin"
  disable_tls_verification = true
  disable_cookies          = true
}


terraform {
  required_providers {
    aviatrix = {
      source = "aviatrixsystems/aviatrix"
    }
    aws = {
      source = "hashicorp/aws"
    }
    guacamole = {
      source = "techBeck03/guacamole"
    }
  }
  required_version = ">= 0.13"
}
