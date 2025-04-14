#!/bin/bash
# AWS EC2 User Data Script for Crypto Live Pipeline
set -euo pipefail
exec > >(tee /var/log/user-data.log) 2>&1

# ======================
# 1. System Configuration
# ======================
echo ">>> Updating system packages..."
sudo yum update -y --skip-broken
sudo yum clean all

# ======================
# 2. Install Dependencies (SIMPLIFIED)
# ======================
echo ">>> Installing base dependencies..."
sudo yum install -y \
    git \
    postgresql13 \
    python3.8 \
    python3.8-devel \
    python3-pip \
    amazon-linux-extras

# Set Python 3.8 as default
sudo alternatives --set python3 /usr/bin/python3.8
sudo alternatives --set pip /usr/bin/pip3.8

# ======================
# 3. Install Tor
# ======================
echo ">>> Installing Tor..."
sudo amazon-linux-extras enable epel -y
sudo yum install -y tor
sudo systemctl enable --now tor

# ======================
# 4. Clone Repository (WITH ERROR HANDLING)
# ======================
echo ">>> Cloning repository..."
if [ ! -d "/home/ec2-user/crypto_live_pipeline" ]; then
  git clone "${github_repo}" /home/ec2-user/crypto_live_pipeline || {
    echo "WARNING: Failed to clone repository, continuing anyway..."
    mkdir -p /home/ec2-user/crypto_live_pipeline
  }
fi

# ======================
# 5. Python Environment (WITH FALLBACK)
# ======================
echo ">>> Setting up Python environment..."
cd /home/ec2-user/crypto_live_pipeline

python3 -m pip install --upgrade pip
python3 -m venv venv
source venv/bin/activate

# Install either requirements.txt or critical packages
if [ -f "requirements.txt" ]; then
  pip install -r requirements.txt || {
    echo "WARNING: Failed some requirements, installing essentials..."
    pip install requests psycopg2-binary python-dotenv
  }
else
  pip install requests psycopg2-binary python-dotenv
fi

# ======================
# 6. Database Setup (WITH RETRIES)
# ======================
echo ">>> Setting up database..."
for i in {1..10}; do
  if PGPASSWORD=${db_password} psql -h ${db_address} -U ${db_username} -d postgres -c "SELECT 1"; then
    echo ">>> Creating tables..."
    PGPASSWORD=${db_password} psql -h ${db_address} -U ${db_username} -d cryptodb -c "
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
    "
    break
  else
    echo "Database not ready (attempt $i/10), waiting..."
    sleep 10
  fi
done

# ======================
# 7. Environment Config
# ======================
echo ">>> Creating .env file..."
cat > /home/ec2-user/crypto_live_pipeline/.env <<EOL
DB_HOST=${db_address}
DB_USER=${db_username}
DB_PASSWORD=${db_password}
DB_NAME=cryptodb
TOR_PASSWORD=tor_poor
EOL
chmod 600 /home/ec2-user/crypto_live_pipeline/.env

# ======================
# 8. Start Application
# ======================
echo ">>> Starting application..."
cd /home/ec2-user/crypto_live_pipeline
source venv/bin/activate
nohup python3 -u new_tokens_pipeline.py >> /var/log/crypto_pipeline.log 2>&1 &

echo ">>> Deployment completed successfully!"
