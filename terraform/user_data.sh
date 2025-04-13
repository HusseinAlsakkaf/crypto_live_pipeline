#!/bin/bash
# AWS EC2 User Data Script for Crypto Live Pipeline
set -euo pipefail  # More strict error handling

# ======================
# 1. System Configuration
# ======================
echo ">>> Updating system packages..."
sudo yum update -y
sudo yum clean all

# Install general dependencies
echo ">>> Installing base dependencies..."
sudo yum install -y git python3 gcc python3-devel

# ======================
# 2. Install PostgreSQL Client
# ======================
echo ">>> Configuring PostgreSQL repository..."
sudo tee /etc/yum.repos.d/pgdg.repo <<EOL
[pgdg13]
name=PostgreSQL 13 for RHEL/CentOS 7 - x86_64
baseurl=https://download.postgresql.org/pub/repos/yum/13/redhat/rhel-7-x86_64
enabled=1
gpgcheck=0
EOL

echo ">>> Installing PostgreSQL client..."
sudo yum install -y postgresql13-13.20
sudo yum clean all

# Verify the installation
echo ">>> PostgreSQL client version:"
psql --version

# ======================
# 3. Install Tor
# ======================
echo ">>> Installing and configuring Tor..."

# Enable EPEL repository
sudo amazon-linux-extras enable epel -y
sudo yum clean all

# Install EPEL release package
sudo yum install -y epel-release

# Install Tor from EPEL repository
sudo yum --enablerepo=epel install -y tor

# Start and enable Tor
sudo systemctl start tor
sudo systemctl enable tor

# Verify Tor is running
if ! systemctl is-active --quiet tor; then
    echo "ERROR: Tor service failed to start!"
    exit 1
fi

# ======================
# 4. Deploy Application
# ======================
echo ">>> Cloning repository..."
if [ ! -d "/home/ec2-user/crypto_live_pipeline" ]; then
    git clone "${github_repo}" /home/ec2-user/crypto_live_pipeline || {
        echo "ERROR: Failed to clone repository!"
        exit 1
    }
fi

cd /home/ec2-user/crypto_live_pipeline || {
    echo "ERROR: Failed to enter project directory!"
    exit 1
}

# SSH Key Setup
echo ">>> Configuring SSH access..."
sudo mkdir -p /home/ec2-user/.ssh
echo "${ssh_key}" | sudo tee -a /home/ec2-user/.ssh/authorized_keys >/dev/null
sudo chmod 600 /home/ec2-user/.ssh/authorized_keys
sudo chown -R ec2-user:ec2-user /home/ec2-user/.ssh

# Python Environment
echo ">>> Setting up Python environment..."
pip3 install --upgrade pip
pip3 install -r requirements.txt || {
    echo "ERROR: Failed to install Python requirements!"
    exit 1
}

# ======================
# 5. Configure Logging
# ======================
echo ">>> Setting up logging..."
sudo mkdir -p /var/log/crypto_pipeline
sudo chown ec2-user:ec2-user /var/log/crypto_pipeline

sudo tee /etc/logrotate.d/crypto_pipeline <<EOL
/var/log/crypto_pipeline/*.log {
    daily
    rotate 7
    compress
    missingok
    notifempty
    create 0644 ec2-user ec2-user
}
EOL

# ======================
# 6. Create .env File
# ======================
echo ">>> Creating .env file..."
cat <<EOL > /home/ec2-user/.env
DB_USER=${db_username}
DB_PASSWORD=${db_password}
DB_HOST=${db_address}
DB_NAME=cryptodb
DB_PORT=5432
TOR_PASSWORD=tor_poor
EOL

sudo chmod 600 /home/ec2-user/.env
sudo chown ec2-user:ec2-user /home/ec2-user/.env

# ======================
# 7. Initialize Database
# ======================
echo ">>> Verifying database connection..."
MAX_RETRIES=10
RETRY_DELAY=10

for ((i=1; i<=$MAX_RETRIES; i++)); do
    if PGPASSWORD=${db_password} psql -h ${db_address} \
       -U ${db_username} \
       -d cryptodb \
       -c "SELECT 1" >/dev/null 2>&1; then
        echo "Database connection successful!"
        break
    else
        echo "Attempt $i/$MAX_RETRIES: Database not ready yet..."
        if [ $i -eq $MAX_RETRIES ]; then
            echo "ERROR: Failed to connect to database after $MAX_RETRIES attempts!"
            exit 1
        fi
        sleep $RETRY_DELAY
    fi
done

echo ">>> Creating 'tokens' table in the database..."
PGPASSWORD=${db_password} psql -h ${db_address} \
       -U ${db_username} \
       -d cryptodb \
       -c "
          CREATE TABLE IF NOT EXISTS tokens (
              address VARCHAR(64) PRIMARY KEY,
              pair_address VARCHAR(64),
              platform VARCHAR(50),
              quote_symbol VARCHAR(20),
              symbol VARCHAR(20),
              name VARCHAR(100),
              logo TEXT,
              
              total_supply NUMERIC(40, 0),
              price NUMERIC(30, 18),
              holder_count INTEGER,
              
              price_change_1m NUMERIC(15, 6),
              price_change_5m NUMERIC(15, 6),
              price_change_1h NUMERIC(15, 6),
              
              burn_ratio NUMERIC(15, 6),
              burn_status VARCHAR(50),
              has_alert BOOLEAN,
              hot_level INTEGER,
              
              quote_reserve NUMERIC(30, 6),
              initial_liquidity NUMERIC(30, 6),
              initial_quote_reserve NUMERIC(30, 6),
              liquidity NUMERIC(30, 6),
              
              top_10_holder_rate NUMERIC(15, 6),
              renounced_mint BOOLEAN,
              renounced_freeze_account BOOLEAN,
              rug_ratio NUMERIC(15, 6),
              
              sniper_count INTEGER,
              smart_degen_count INTEGER,
              renowned_count INTEGER,
              
              market_cap NUMERIC(30, 6),
              is_wash_trading BOOLEAN,
              creator_balance_rate NUMERIC(15, 6),
              creator_token_status VARCHAR(50),
              rat_trader_amount_rate NUMERIC(15, 6),
              bluechip_owner_percentage NUMERIC(15, 6),
              
              volume NUMERIC(30, 6),
              swaps INTEGER,
              buys INTEGER,
              sells INTEGER,
              
              dev_token_burn_amount NUMERIC(30, 6),
              dev_token_burn_ratio NUMERIC(15, 6),
              
              cto_flag BOOLEAN,
              twitter_change_flag BOOLEAN,
              
              open_timestamp TIMESTAMP,
              bot_degen_count INTEGER,
              
              twitter_username VARCHAR(100),
              website TEXT,
              telegram TEXT,
              
              creator VARCHAR(64),
              status VARCHAR(20) DEFAULT 'alive',
              creation_timestamp TIMESTAMP
          );

          -- Indexes
          CREATE INDEX IF NOT EXISTS idx_status ON tokens(status);
          CREATE INDEX IF NOT EXISTS idx_platform ON tokens(platform);
          CREATE INDEX IF NOT EXISTS idx_status_platform ON tokens(status, platform);
          CREATE INDEX IF NOT EXISTS idx_creation_timestamp ON tokens(creation_timestamp);
          CREATE INDEX IF NOT EXISTS idx_price ON tokens(price);
          CREATE INDEX IF NOT EXISTS idx_liquidity ON tokens(liquidity);
        " || {
          echo "ERROR: Failed to create database tables!"
          exit 1
        }

# ======================
# 8. Start Application
# ======================
echo ">>> Starting pipeline..."
{
    echo "=== Startup Timestamp: $(date) ==="
    echo "=== System Info ==="
    echo "Hostname: $(hostname)"
    echo "IP: $(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)"
    echo "=== Tor IP: $(curl --socks5 127.0.0.1:9050 ifconfig.me) ==="
    
    # Start the application
    cd /home/ec2-user/crypto_live_pipeline
    nohup python3 -u new_tokens_pipeline.py >> /var/log/crypto_pipeline/pipeline.log 2>&1 &
    APP_PID=$!
    
    echo "Application started with PID: $APP_PID"
    echo "=== Startup Complete ==="
} | sudo tee -a /var/log/crypto_pipeline/startup.log

# ======================
# 9. Monitoring Setup
# ======================
echo ">>> Installing monitoring tools..."
sudo yum install -y amazon-cloudwatch-agent
sudo tee /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<EOL
{
    "logs": {
        "logs_collected": {
            "files": {
                "collect_list": [
                    {
                        "file_path": "/var/log/crypto_pipeline/*.log",
                        "log_group_name": "crypto_pipeline",
                        "log_stream_name": "$(curl -s http://169.254.169.254/latest/meta-data/instance-id)"
                    }
                ]
            }
        }
    }
}
EOL

sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
    -a fetch-config \
    -m ec2 \
    -s \
    -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

echo ">>> Deployment complete!"