#!/bin/bash
# AWS EC2 User Data Script for Crypto Live Pipeline
set -euo pipefail
exec > >(tee /var/log/user-data.log) 2>&1

# ======================
# 1. System Configuration
# ======================
echo ">>> Updating system packages..."
sudo yum update -y
sudo yum clean all

echo ">>> Installing base dependencies..."
sudo yum install -y git gcc 

# ======================
# 2. Install Python 3.8
# ======================
echo ">>> Installing Python 3.8..."
sudo amazon-linux-extras enable python3.8 -y
sudo yum install -y python38 python38-devel python38-pip
sudo alternatives --set python3 /usr/bin/python3.8
sudo alternatives --set pip /usr/bin/pip3.8

# ======================
# 3. Install PostgreSQL Client
# ======================
echo ">>> Installing PostgreSQL client..."
sudo tee /etc/yum.repos.d/pgdg.repo <<EOL
[pgdg13]
name=PostgreSQL 13 for RHEL/CentOS 7 - x86_64
baseurl=https://download.postgresql.org/pub/repos/yum/13/redhat/rhel-7-x86_64
enabled=1
gpgcheck=0
EOL

sudo yum install -y postgresql13
echo "PostgreSQL client version: $(psql --version)"

# ======================
# 4. Install Tor
# ======================
echo ">>> Installing Tor..."
sudo amazon-linux-extras enable epel -y
sudo yum install -y tor
sudo systemctl enable --now tor

# ======================
# 5. Clone Repository
# ======================
echo ">>> Cloning repository..."
MAX_RETRIES=3
for i in $(seq 1 $MAX_RETRIES); do
  if [ ! -d "/home/ec2-user/crypto_live_pipeline" ]; then
    git clone "${github_repo}" /home/ec2-user/crypto_live_pipeline && break || {
      echo "Attempt $i/$MAX_RETRIES failed. Retrying..."
      sleep 10
    }
  fi
done

# ======================
# 6. Python Environment
# ======================
echo ">>> Setting up Python environment..."
cd /home/ec2-user/crypto_live_pipeline || {
  echo "ERROR: Project directory missing!"
  exit 1
}

python3 -m pip install --upgrade pip
python3 -m venv venv
source venv/bin/activate

# Install requirements with fallback
if [ -f "requirements.txt" ]; then
  pip install -r requirements.txt || {
    echo "WARNING: Failed to install some requirements, installing critical ones..."
    pip install requests psycopg2-binary python-dotenv
  }
fi

# ======================
# 7. Database Setup
# ======================
echo ">>> Setting up database..."
sudo mkdir -p /var/log/crypto_pipeline
sudo chown ec2-user:ec2-user /var/log/crypto_pipeline

# Wait for database to be available
for i in {1..30}; do
  if PGPASSWORD=${db_password} psql -h ${db_address} -U ${db_username} -d postgres -c "SELECT 1" &>/dev/null; then
    echo "Database connection successful!"
    break
  else
    echo "Attempt $i/30: Waiting for database..."
    sleep 10
  fi
done

# Create tables
echo ">>> Creating database tables..."
PGPASSWORD=${db_password} psql -h ${db_address} -U ${db_username} -d cryptodb <<EOL
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
CREATE INDEX IF NOT EXISTS idx_status ON tokens(status);
CREATE INDEX IF NOT EXISTS idx_platform ON tokens(platform);
EOL

# ======================
# 8. Environment Configuration
# ======================
echo ">>> Creating .env file..."
cat > /home/ec2-user/crypto_live_pipeline/.env <<EOL
DB_HOST=${db_address}
DB_USER=${db_username}
DB_PASSWORD=${db_password}
DB_NAME=cryptodb
DB_PORT=5432
TOR_PASSWORD=tor_poor
EOL
chmod 600 /home/ec2-user/crypto_live_pipeline/.env

# ======================
# 9. Process Monitoring
# ======================
echo ">>> Setting up process monitor..."
sudo tee /home/ec2-user/monitor.sh <<EOL
#!/bin/bash
while true; do
    if ! pgrep -f "python3.*new_tokens_pipeline.py" >/dev/null; then
        echo "\$(date): Process not found! Restarting..." >> /var/log/crypto_pipeline/monitor.log
        cd /home/ec2-user/crypto_live_pipeline
        source venv/bin/activate
        nohup python3 -u new_tokens_pipeline.py >> /var/log/crypto_pipeline/pipeline.log 2>&1 &
    fi
    sleep 60
done
EOL

sudo chmod +x /home/ec2-user/monitor.sh
sudo chown ec2-user:ec2-user /home/ec2-user/monitor.sh

# ======================
# 10. Start Application
# ======================
echo ">>> Starting application..."
cd /home/ec2-user/crypto_live_pipeline
source venv/bin/activate
nohup python3 -u new_tokens_pipeline.py >> /var/log/crypto_pipeline/pipeline.log 2>&1 &

# Start monitor in background
nohup /home/ec2-user/monitor.sh >> /var/log/crypto_pipeline/monitor.log 2>&1 &

echo ">>> Deployment completed successfully!"