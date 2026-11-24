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
  description = "Full URI of an existing Linux AMD64 container image, tagged with the app version, for example ghcr.io/adish98/menteetest:1.2.4."
  type        = string
}

variable "container_port" {
  description = "Port the application listens on inside the container. Used by the task, target group, and security groups, and passed to the app as PORT."
  type        = number
  default     = 8080

  validation {
    condition     = var.container_port >= 1024 && var.container_port <= 65535
    error_message = "Use an unprivileged port (1024-65535); the container runs as non-root with all capabilities dropped."
  }
}
