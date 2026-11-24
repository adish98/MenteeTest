variable "name" {
  description = "Application resource and container name."
  type        = string
  default     = "exam-adi-shmul"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,19}$", var.name))
    error_message = "Use 1-20 lowercase letters, digits, or hyphens, starting with a letter."
  }
}

variable "image_uri" {
  description = "Full URI of an existing Linux AMD64 container image, preferably pinned by digest."
  type        = string
}

variable "execution_role_arn" {
  description = "Optional existing ECS task execution role ARN. Leave empty to have Terraform create one with the required permissions boundary."
  type        = string
  default     = ""

  validation {
    condition     = var.execution_role_arn == "" || can(regex("^arn:aws(-[a-z]+)*:iam::[0-9]{12}:role/.+$", var.execution_role_arn))
    error_message = "execution_role_arn must be empty or a valid IAM role ARN."
  }
}

variable "execution_role_permissions_boundary" {
  description = "Permissions boundary policy ARN required when creating the ECS task execution role."
  type        = string
  default     = "arn:aws:iam::030454160336:policy/candidate-exam-boundary"
}
