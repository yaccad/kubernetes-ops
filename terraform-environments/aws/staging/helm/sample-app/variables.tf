variable "repository" {
  default = "954793382213.dkr.ecr.us-east-1.amazonaws.com/sample-repo"
}

variable "tag" {
  default = "sample-app8"
}

variable "namespace" {
  type        = string
  default     = "sample-app"
  description = "Namespace to deploy the image into"
}

variable "fullnameOverride" {
  type        = string
  default     = "sample-app"
  description = "Chart name"
}