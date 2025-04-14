#!/bin/bash
# AWS EC2 User Data Script - Minimal Working Version
exec > >(tee /var/log/user-data.log) 2>&1

# 1. INSTALL JUST THE ESSENTIALS
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
python3 -m pip install -r requirements.txt

# 4. DATABASE SETUP
PGPASSWORD=${db_password} psql -h ${db_address} -U ${db_username} -d cryptodb -c "
  CREATE TABLE IF NOT EXISTS tokens (
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
  );"

# 5. START APPLICATION
nohup python3 new_tokens_pipeline.py > pipeline.log 2>&1 &

echo "SUCCESS: Deployment completed"
