variable "cluster_name" {
  description = "Name of the cluster"
  type        = string
  default     = "eks-cas-aft-yanivzl"
}

variable "region" {
  description = "Code of the region"
  type        = string
  default     = "us-west-1"
}

variable "azs" {
  description = "List of availabity zones"
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b", "us-west-2c"]
}

variable "vpc_cidr" {
  description = "CIDR of vpc"
  type        = string
  default     = "10.0.0.0/16"
}

variable "jenkins_admin_user" {
  description = "Jenkins admin user name"
  type        = string
  sensitive   = true
}

variable "jenkins_admin_password" {
  description = "Jenkins admin user password"
  type        = string
  sensitive   = true
}
