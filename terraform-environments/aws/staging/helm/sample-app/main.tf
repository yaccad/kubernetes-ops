locals {
  aws_region       = "us-east-1"
  environment_name = "staging"
  tags = {
    ops_env              = "${local.environment_name}"
    ops_managed_by       = "terraform",
    ops_source_repo      = "kubernetes-ops",
    ops_source_repo_path = "terraform-environments/aws/${local.environment_name}/helm/sample-app",
    ops_owners           = "devops",
  }
}

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 3.37.0"
    }
    random = {
      source = "hashicorp/random"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "2.3.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">=2.20"
    }
  }

  backend "remote" {
    # Update to your Terraform Cloud organization
    organization = "Accadius"

    workspaces {
      name = "kubernetes-ops-staging-sample-app"
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
      name = "kubernetes-ops-${local.environment_name}-5-route53-hostedzone"
    }
  }
}

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

# Helm values file templating
data "template_file" "helm_values" {
  template = file("${path.module}/helm_values.yaml")
  # Parameters you want to pass into the helm_values.yaml.tpl file to be templated
  vars = {
    fullnameOverride = "${var.namespace}"
    repository       = var.repository
    tag              = var.tag
  }
}
module "sample-app" {
  source = "github.com/ManagedKube/kubernetes-ops//terraform-modules/aws/helm/helm_generic?ref=v1.0.30"
  # this is the helm repo add URL
  repository = "https://helm-charts.managedkube.com"
  # This is the helm repo add name
  official_chart_name = "standard-application"
  # This is what you want to name the chart when deploying
  user_chart_name = var.fullnameOverride
  # The helm chart version you want to use
  helm_version = "1.0.12"
  # The namespace you want to install the chart into - it will create the namespace if it doesnt exist
  namespace = var.namespace
  # The helm chart values file
  helm_values = data.template_file.helm_values.rendered
}




provider "kubernetes" {
  host                   = data.terraform_remote_state.eks.outputs.cluster_endpoint
  cluster_ca_certificate = base64decode(data.terraform_remote_state.eks.outputs.cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    args        = ["eks", "get-token", "--cluster-name", "${local.environment_name}"]
    command     = "aws"
  }
}

resource "kubernetes_ingress_v1" "sample-app" {

  wait_for_load_balancer = true
  metadata {
    name      = "sample-app"
    namespace = "sample-app"
    annotations = {
      "cert-manager.io/cluster-issuer" = "letsencrypt"
      # "nginx.ingress.kubernetes.io/rewrite-target" = "/"
      "kubernetes.io/ingress.class" = "nginx"
    }
  }
  spec {
    rule {
      host = "api.k8s.staging.accadius.com"
      http {
        path {
          # path = "/*"
          backend {
            service {
              name = "sample-app-standard-application"
              port {
                number = 443
              }
            }

          }
        }
      }
    }
    tls {
      hosts       = ["api.k8s.staging.accadius.com"]
      secret_name = "tls-sample-app"
    }

  }
}