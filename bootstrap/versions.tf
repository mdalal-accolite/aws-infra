terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # No backend block on purpose. This stack runs with LOCAL state, because it
  # is the thing that creates the remote state bucket. Commit the resulting
  # terraform.tfstate file or store it somewhere safe - it is small and only
  # changes when you change CI permissions.
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform-bootstrap"
    }
  }
}
