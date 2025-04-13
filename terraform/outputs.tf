output "instance_public_ip" {
  description = "Public IP of the EC2 instance"
  value       = aws_instance.pipeline.public_ip
}

output "ssh_command" {
  description = "Command to SSH into the instance"
  value       = "ssh -i '${var.ssh_key_name}.pem' ec2-user@${aws_instance.pipeline.public_ip}"
}