#!/bin/bash
# AWS EC2 User Data Script for Crypto Live Pipeline
set -euo pipefail

# ======================
# 0. Logging Setup (NEW - Added first to capture all output)
# ======================
exec > >(tee /var/log/user-data.log) 2>&1
echo "=== Starting user-data script ==="

# ======================
# 1. System Configuration
# ======================
echo ">>> Updating system packages..."
sudo yum update -y
sudo yum clean all

# Install general dependencies (NEW - Removed python3 to avoid conflicts)
echo ">>> Installing base dependencies..."
sudo yum install -y git gcc 

# ======================
# 2. Install Python 3.8 (NEW - Moved before other installs)
# ======================
echo ">>> Installing Python 3.8..."
sudo amazon-linux-extras enable python3.8 -y
sudo yum install -y python3.8 python3.8-devel
sudo alternatives --set python3 /usr/bin/python3.8
echo "Python version: $(python3 --version)"

# ======================
# 3. Install PostgreSQL Client
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
echo "PostgreSQL client version: $(psql --version)"

# ======================
# 4. Install Tor
# ======================
echo ">>> Installing Tor..."
sudo amazon-linux-extras enable epel -y
sudo yum install -y epel-release tor
sudo systemctl enable --now tor

# ======================
# 5. Deploy Application
# ======================
echo ">>> Cloning repository..."
if [ ! -d "/home/ec2-user/crypto_live_pipeline" ]; then
    git clone "${github_repo}" /home/ec2-user/crypto_live_pipeline
fi

# ======================
# 6. Python Environment (NEW - Simplified)
# ======================
echo ">>> Setting up Python environment..."
python3 -m pip install --upgrade pip
python3 -m venv /home/ec2-user/venv
source /home/ec2-user/venv/bin/activate

# NEW - Handle requirements.txt fallback
if [ -f "/home/ec2-user/crypto_live_pipeline/requirements.txt" ]; then
    echo ">>> Installing requirements..."
    pip install -r /home/ec2-user/crypto_live_pipeline/requirements.txt || {
        echo "WARNING: Failed to install some requirements, attempting fallback..."
        pip install requests==2.28.0 psycopg2-binary python-dotenv
    }
else
    echo ">>> Installing default packages..."
    pip install requests psycopg2-binary python-dotenv
fi

# ======================
# 7. Database Setup (NEW - Improved waiting logic)
# ======================
echo ">>> Waiting for database..."
for i in {1..30}; do
    if PGPASSWORD=${db_password} psql -h ${db_address} -U ${db_username} -d postgres -c "SELECT 1" &>/dev/null; then
        break
    fi
    echo "Attempt $i/30: Waiting for database..."
    sleep 10
done

# NEW - Verify connection before creating tables
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
);"

# ======================
# 8. Environment Configuration (NEW - Moved to project dir)
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
# 9. Start Application (NEW - Added process manager)
# ======================
echo ">>> Starting application..."
cd /home/ec2-user/crypto_live_pipeline
nohup python3 -u new_tokens_pipeline.py >> /var/log/crypto_pipeline/pipeline.log 2>&1 &

# NEW - Basic process monitoring
echo ">>> Setting up process monitor..."
cat > /home/ec2-user/monitor.sh <<'EOL'
#!/bin/bash
while true; do
    if ! pgrep -f "python3.*new_tokens_pipeline.py" >/dev/null; then
        echo "Process crashed! Restarting..."
        cd /home/ec2-user/crypto_live_pipeline
        nohup python3 -u new_tokens_pipeline.py >> /var/log/crypto_pipeline/pipeline.log 2>&1 &
    fi
    sleep 60
done
EOL

chmod +x /home/ec2-user/monitor.sh
nohup /home/ec2-user/monitor.sh >> /var/log/crypto_pipeline/monitor.log 2>&1 &

echo ">>> Deployment complete!"