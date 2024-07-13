variable "region" {
  description = "region"
  type        = string
  default     = "asia-northeast1"
}

variable "zone" {
  description = "zone"
  type        = string
  default     = "asia-northeast1-c"
}

variable "project" {
  description = "project"
  type        = string
  validation {
    condition     = length(var.project) > 0
    error_message = "Project must not be empty"
  }
}
