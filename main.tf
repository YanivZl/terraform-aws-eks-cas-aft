locals {
  tags = {
    Name        = var.cluster_name
    Environment = "Development"
    Description = "AFT DevOps Task"
  }
}

################################################################################
# Cluster
################################################################################

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name                   = var.cluster_name
  cluster_version                = "1.29"
  cluster_endpoint_public_access = true

  # Give the Terraform identity admin access to the cluster
  # which will allow resources to be deployed into the cluster
  enable_cluster_creator_admin_permissions = true

  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
    aws-ebs-csi-driver = {
      most_recent = true
    }
  }

  iam_role_additional_policies = {
    AmazonEBSCSIDriverPolicy = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  }

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  eks_managed_node_groups = {
    mng1 = {
      instance_types = ["t3.medium"]

      min_size     = 1
      max_size     = 5
      desired_size = 2
    }
  }

  eks_managed_node_group_defaults = {
    ami_type                              = "AL2_x86_64"
    instance_types                        = ["t3.medium"]
    attach_cluster_primary_security_group = false
    iam_role_additional_policies = {
      AmazonEBSCSIDriverPolicy = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
    }
  }

  tags = local.tags
}

data "aws_eks_cluster_auth" "this" {
  name = var.cluster_name
}

################################################################################
# EKS Blueprints Addons
################################################################################

module "eks_blueprints_addons" {
  source  = "aws-ia/eks-blueprints-addons/aws"
  version = "~> 1.14"

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider_arn = module.eks.oidc_provider_arn

  enable_aws_load_balancer_controller = true

  depends_on = [
    # Wait for EBS CSI, etc. to be installed first
    module.eks
  ]

  # Add-ons
  enable_cluster_autoscaler     = true
  enable_metrics_server         = true

  helm_releases = {
    jenkins = {
      name       = "jenkins"
      repository = "https://charts.jenkins.io"
      chart      = "jenkins"
      namespace  = "jenkins"
      create_namespace = true

      values = [
        "${file("./jenkins/jenkins-chart-values.yaml")}"
      ]

      set_sensitive = [
        {
          name  = "controller.admin.username"
          value = var.jenkins_admin_user
        },
        {
          name  = "controller.admin.password"
          value = var.jenkins_admin_password
        }
      ]
    }
  }

  tags = local.tags
}

################################################################################
# Kubernetes Manifests
################################################################################

resource "kubectl_manifest" "jenkins_service_account" {
  depends_on = [ module.eks_blueprints_addons.helm_releases ]
  yaml_body = file("./jenkins/jenkins-service-account.yaml")
}

resource "kubectl_manifest" "jenkins_cluster_role" {
  depends_on = [ module.eks_blueprints_addons.helm_releases ]
  yaml_body = file("./jenkins/jenkins-cluster-role.yaml")
}

resource "kubectl_manifest" "jenkins_cluster_role_binding" {
  depends_on = [ module.eks_blueprints_addons.helm_releases ]
  yaml_body = file("./jenkins/jenkins-cluster-role-binding.yaml")
}

################################################################################
# Supporting Resources
################################################################################

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = var.cluster_name
  cidr = var.vpc_cidr

  azs             = var.azs
  private_subnets = [for k, v in var.azs : cidrsubnet(var.vpc_cidr, 4, k)]
  public_subnets  = [for k, v in var.azs : cidrsubnet(var.vpc_cidr, 8, k + 48)]

  enable_nat_gateway = true
  single_nat_gateway = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }

  tags = local.tags
}