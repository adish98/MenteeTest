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
