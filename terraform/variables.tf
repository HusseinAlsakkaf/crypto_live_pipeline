variable "ssh_key_name" {
  description = "crypto-key"
  type        = string
  default     = "crypto-key"  # Replace with your key
}

variable "github_repo" {
  description = "GitHub repo URL to clone your project"
  type        = string
  default     = "https://github.com/your_username/crypto_live_pipeline.git"
}