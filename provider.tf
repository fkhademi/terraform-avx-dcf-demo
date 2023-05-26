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

terraform {
  required_providers {
    aviatrix = {
      source = "aviatrixsystems/aviatrix"
    }
    aws = {
      source = "hashicorp/aws"
    }
  }
  required_version = ">= 0.13"
}
