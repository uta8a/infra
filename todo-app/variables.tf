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

variable "bucket_region" {
  description = "bucket region"
  type        = string
  default     = "ASIA-NORTHEAST1"
}

variable "path" {
  description = "cloud functions source code path"
  type        = string
  validation {
    condition     = length(var.path) > 0
    error_message = "Path must not be empty"
  }
}

variable "firestore_database" {
  description = "firestore database"
  type        = string
  validation {
    condition     = length(var.firestore_database) > 0
    error_message = "Firestore database must not be empty"
  }
}

variable "member" {
  description = "User:<email> for cloud functions authentication"
  type        = string
  validation {
    condition     = length(var.member) > 0
    error_message = "Member must not be empty"
  }
}
