#!/bin/bash
# AWS EC2 User Data Script - Final Working Version
exec > >(tee /var/log/user-data.log) 2>&1

# 1. INSTALL ESSENTIALS (with PostgreSQL repo setup)
sudo tee /etc/yum.repos.d/pgdg.repo <<EOL
[pgdg13]
name=PostgreSQL 13 for RHEL/CentOS 7 - x86_64
baseurl=https://download.postgresql.org/pub/repos/yum/13/redhat/rhel-7-x86_64
enabled=1
gpgcheck=0
EOL

sudo yum install -y \
    git \
    postgresql13 \
    python3 \
    python3-pip

# 2. CLONE REPO (with retries)
for i in {1..3}; do
  git clone "${github_repo}" /home/ec2-user/crypto_live_pipeline && break || sleep 10
done

# 3. SETUP ENVIRONMENT
cd /home/ec2-user/crypto_live_pipeline || exit

# Install critical packages first with explicit versions
sudo pip3 install --upgrade pip
sudo pip3 install \
    requests==2.28.0 \
    python-dotenv \
    psycopg2-binary

# Then try full requirements
pip3 install -r requirements.txt || echo "Some requirements failed"

# 4. FIX PERMISSIONS (in case clone was done as root)
sudo chown -R ec2-user:ec2-user /home/ec2-user/crypto_live_pipeline

# 5. DATABASE SETUP (with retries)
for i in {1..5}; do
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
    CREATE INDEX IF NOT EXISTS idx_platform ON tokens(platform);
  " && break || sleep 15
done

# 6. START APPLICATION
cd /home/ec2-user/crypto_live_pipeline
nohup python3 new_tokens_pipeline.py > pipeline.log 2>&1 &

echo "SUCCESS: Deployment completed. Check /var/log/user-data.log and ~/crypto_live_pipeline/pipeline.log for details."