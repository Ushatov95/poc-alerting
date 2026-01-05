variable "subscription_id" {
  description = "Azure subscription ID where the POC will deploy."
  type        = string
}

variable "location" {
  type    = string
  default = "westeurope"
}

variable "workload_rg_name" {
  type    = string
  default = "rg-poc-kv-workload"
}

variable "monitoring_rg_name" {
  type    = string
  default = "rg-poc-kv-monitoring"
}

variable "notification_email" {
  description = "Email to receive alert notifications (for POC)."
  type        = string
}

variable "monitoring_profile" {
  description = "dev|test|prod. Controls which alerts are enabled by default."
  type        = string
  default     = "prod"
  validation {
    condition     = contains(["dev", "test", "prod"], var.monitoring_profile)
    error_message = "monitoring_profile must be one of: dev, test, prod."
  }
}
