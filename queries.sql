-- Active: 1744141040663@@127.0.0.1@5432@crypto_live_pipeline
CREATE TABLE tokens (
    address VARCHAR(64) PRIMARY KEY,
    pair_address VARCHAR(64),
    platform VARCHAR(50),
    quote_symbol VARCHAR(20),
    symbol VARCHAR(20),
    name VARCHAR(100),
    logo TEXT,
    
    total_supply NUMERIC(40, 0),  -- Large supply tokens (e.g., Shiba Inu)
    price NUMERIC(30, 18),         -- Handle tokens with very small prices (18 decimals)
    holder_count INTEGER,
    
    price_change_1m NUMERIC(15, 6),  -- Can handle ±999,999.999999% changes
    price_change_5m NUMERIC(15, 6),
    price_change_1h NUMERIC(15, 6),
    
    burn_ratio NUMERIC(15, 6),
    burn_status VARCHAR(50),
    has_alert BOOLEAN,
    hot_level INTEGER,
    
    quote_reserve NUMERIC(30, 6),        -- Can handle up to 999,999,999,999.999999
    initial_liquidity NUMERIC(30, 6),
    initial_quote_reserve NUMERIC(30, 6),
    liquidity NUMERIC(30, 6),
    
    top_10_holder_rate NUMERIC(15, 6),   -- Can represent 999,999.999999%
    renounced_mint BOOLEAN,
    renounced_freeze_account BOOLEAN,
    rug_ratio NUMERIC(15, 6),
    
    sniper_count INTEGER,
    smart_degen_count INTEGER,
    renowned_count INTEGER,
    
    market_cap NUMERIC(30, 6),           -- Can handle $999 trillion market caps
    is_wash_trading BOOLEAN,
    creator_balance_rate NUMERIC(15, 6),
    creator_token_status VARCHAR(50),
    rat_trader_amount_rate NUMERIC(15, 6),
    bluechip_owner_percentage NUMERIC(15, 6),
    
    volume NUMERIC(30, 6),               -- Large volume numbers
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
-- Index on status
CREATE INDEX idx_status ON tokens(status);
CREATE INDEX idx_platform ON tokens(platform);
CREATE INDEX idx_status_platform ON tokens(status, platform);
CREATE INDEX idx_creation_timestamp ON tokens(creation_timestamp);
CREATE INDEX idx_price ON tokens(price);
CREATE INDEX idx_liquidity ON tokens(liquidity);