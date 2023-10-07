locals {
  aws_region       = "us-east-1"
  environment_name = "staging"
  tags = {
    ops_env              = "${local.environment_name}"
    ops_managed_by       = "terraform",
    ops_source_repo      = "kubernetes-ops",
    ops_source_repo_path = "terraform-environments/aws/${local.environment_name}/helm/kube-prometheus-stack",
    ops_owners           = "devops",
  }
}

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~>3.37"
    }
    random = {
      source = "hashicorp/random"
    }

    helm = {
      source  = "hashicorp/helm"
      version = ">=2.3.0"
    }
    kubectl = {
      source = "gavinbunney/kubectl"
    }
  }

  backend "remote" {
    # Update to your Terraform Cloud organization
    organization = "Accadius"

    workspaces {
      name = "kubernetes-ops-staging-helm-kube-prometheus-stack"
    }
  }
}

provider "aws" {
  region = local.aws_region
}

data "terraform_remote_state" "eks" {
  backend = "remote"
  config = {
    # Update to your Terraform Cloud organization
    organization = "Accadius"
    workspaces = {
      name = "kubernetes-ops-${local.environment_name}-20-eks"
    }
  }
}

data "terraform_remote_state" "route53_hosted_zone" {
  backend = "remote"
  config = {
    # Update to your Terraform Cloud organization
    organization = "Accadius"
    workspaces = {
      name = "kubernetes-ops-staging-5-route53-hostedzone"
    }
  }
}

#
# EKS authentication
# # https://registry.terraform.io/providers/hashicorp/helm/latest/docs#exec-plugins
provider "helm" {
  kubernetes {
    host                   = data.terraform_remote_state.eks.outputs.cluster_endpoint
    cluster_ca_certificate = base64decode(data.terraform_remote_state.eks.outputs.cluster_certificate_authority_data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      args        = ["eks", "get-token", "--cluster-name", "${local.environment_name}"]
      command     = "aws"
    }
  }
}

data "aws_eks_cluster_auth" "main" {
  name = local.environment_name
}

provider "kubectl" {
  host                   = data.terraform_remote_state.eks.outputs.cluster_endpoint
  cluster_ca_certificate = base64decode(data.terraform_remote_state.eks.outputs.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.main.token
  load_config_file       = false
}

#
# Helm - kube-prometheus-stack
#
module "kube-prometheus-stack" {
  source = "github.com/ManagedKube/kubernetes-ops//terraform-modules/aws/helm/kube-prometheus-stack?ref=v1.0.15"

  helm_values = file("${path.module}/values.yaml")
  # The helm chart version you want to use
  helm_version = "51.2.0"

  depends_on = [
    data.terraform_remote_state.eks
  ]
}
