# Create a security group allowing SSH and outbound traffic
resource "aws_security_group" "pipeline_sg" {
  name        = "pipeline-sg"
  description = "Allow SSH and all outbound traffic"

ingress {
  from_port   = 22
  to_port     = 22
  protocol    = "tcp"
  cidr_blocks = [var.ssh_allowed_ip]
}

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

resource "aws_instance" "pipeline" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t2.micro"
  key_name      = var.ssh_key_name
  
  user_data = templatefile("${path.module}/user_data.sh", {
    github_repo  = var.github_repo
    db_username  = aws_db_instance.pipeline_db.username
    db_password  = var.db_password
    db_address   = aws_db_instance.pipeline_db.address
    ssh_key      = file("/home/hoss/.ssh/${var.ssh_key_name}.pub") 
  })
  
  vpc_security_group_ids = [aws_security_group.pipeline_sg.id]

  tags = {
    Name = "CryptoPipeline"
  }
}

# Create an RDS PostgreSQL instance
resource "aws_db_instance" "pipeline_db" {
  allocated_storage    = 20
  storage_type         = "gp2"
  engine               = "postgres"
  engine_version       = "13.16"  # Updated to a supported version
  instance_class       = "db.t3.micro"
  db_name              = "cryptodb"
  username             = "crypto_user"
  password             = var.db_password
  parameter_group_name = "default.postgres13"
  skip_final_snapshot  = true   # For testing purposes only; set to false in production

  vpc_security_group_ids = [aws_security_group.rds_sg.id]

  tags = {
    Name = "CryptoPipelineDB"
  }
}

# Security group for the RDS instance
resource "aws_security_group" "rds_sg" {
  name        = "rds-sg"
  description = "Allow inbound traffic from EC2 instance to RDS"

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Restrict to EC2 security group in production!
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}