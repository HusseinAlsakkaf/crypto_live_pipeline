#!/bin/bash
# AWS EC2 User Data Script - Optimized Version
exec > >(tee /var/log/user-data.log) 2>&1

# 1. INSTALL ESSENTIALS (with Python 3.8 and PostgreSQL)
sudo tee /etc/yum.repos.d/pgdg.repo <<EOL
[pgdg13]
name=PostgreSQL 13 for RHEL/CentOS 7 - x86_64
baseurl=https://download.postgresql.org/pub/repos/yum/13/redhat/rhel-7-x86_64
enabled=1
gpgcheck=0
EOL

sudo amazon-linux-extras install -y python3.8 postgresql13
sudo alternatives --set python /usr/bin/python3.8

sudo yum install -y \
    git \
    postgresql13 \
    python3-pip \
    python3-devel

# 2. CLONE REPO (with retries)
for i in {1..3}; do
  git clone "${github_repo}" /home/ec2-user/crypto_live_pipeline && break || sleep 10
done

# 3. SETUP ENVIRONMENT
cd /home/ec2-user/crypto_live_pipeline || exit

# Install requirements
sudo pip3.8 install --upgrade pip
sudo pip3.8 install -r requirements.txt


# Configure fake-useragent with fallback
echo "Setting up UserAgent fallback..."
sudo -u ec2-user mkdir -p /home/ec2-user/crypto_live_pipeline/utils/
sudo -u ec2-user bash -c 'cat > /home/ec2-user/crypto_live_pipeline/utils/useragent.py << "EOL"
"""Fallback user agents"""
DEFAULT_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36"

def get_random():
    return DEFAULT_AGENT
EOL'

# Fix permissions for useragent.py
sudo chmod +x /home/ec2-user/crypto_live_pipeline/utils/useragent.py
sudo chown ec2-user:ec2-user /home/ec2-user/crypto_live_pipeline/utils/useragent.py
# 4. FIX PERMISSIONS
sudo chown -R ec2-user:ec2-user /home/ec2-user/crypto_live_pipeline

# 5. DATABASE SETUP (with retries)
# Create SQL file with table schema
cat > /tmp/create_table.sql <<EOL
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

# Execute the SQL with retries
for i in {1..5}; do
  PGPASSWORD=${db_password} psql -h ${db_address} -U ${db_username} -d cryptodb -f /tmp/create_table.sql && break || sleep 15
done

# 6. START APPLICATION
cd /home/ec2-user/crypto_live_pipeline
sudo -u ec2-user nohup python3.8 new_tokens_pipeline.py > pipeline.log 2>&1 &

echo "SUCCESS: Deployment completed. Check /var/log/user-data.log and ~/crypto_live_pipeline/pipeline.log for details."