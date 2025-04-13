variable "github_repo" {
  description = "GitHub repo URL to clone the project"
  type        = string
  default     = "https://github.com/HusseinAlsakkaf/crypto_live_pipeline.git"
}

variable "db_password" {
  description = "Password for the RDS PostgreSQL instance"
  type        = string
  sensitive   = true
}

variable "ssh_key_name" {
  description = "Name of the SSH key pair to use for EC2 instance access"
  type        = string
  default     = "new-crypto-key"
}

variable "ssh_allowed_ip" {
  description = "IP address allowed to SSH into the instance"
  type        = string
  default     = "0.0.0.0/0"  # Default allows all IPs (update for production)
}