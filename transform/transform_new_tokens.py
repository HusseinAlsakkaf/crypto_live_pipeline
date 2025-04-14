

import pandas as pd
import numpy as np
from typing import Dict, Any
from datetime import datetime
import numpy as np
#from extract.extract_new_tokens import make_request
import logging
# Now you can use absolute imports
from utils.clean_numeric_columns import clean_numeric_columns
from utils.convert_boolean_columns import convert_boolean_columns
from utils.flatten_json import flatten_json






def transform_new_tokens(json_data: dict) -> pd.DataFrame:
    """Transforms and cleans GMGN JSON data into a properly typed DataFrame."""
    logging.info("╔════════════════════════════════════════════╗")
    logging.info("║       TRANSFORMATION PHASE                 ║")
    logging.info("╚════════════════════════════════════════════╝\n")
    
    # Early return if no data
    if not json_data or not json_data.get('data', {}).get('pairs'):
        logging.warning("No data found in JSON input.")
        return pd.DataFrame()

    # Extract and flatten the raw data
    raw_data = json_data["data"]["pairs"]
    flat_records = [flatten_json(item) for item in raw_data]
    df = pd.DataFrame(flat_records)
    
    # Drop unnecessary columns
    cols_to_drop = [
        'id', 'pool_type', 'quote_address', 'base_token_info_launchpad_status',
        'base_token_info_buy_tax', 'base_token_info_sell_tax', 'base_token_info_is_honeypot',
        'base_token_info_renounced', 'base_token_info_dexscr_ad', 'base_token_info_dexscr_update_link',
        'base_token_info_is_open_source', 'base_token_info_lockInfo', 'base_token_info_progress'
    ]
    df.drop(columns=[col for col in cols_to_drop if col in df.columns], inplace=True)
    
    # Column combinations and filling missing values
    column_combinations = [
        ('pool_type_str', 'launchpad'),
        ('base_address', 'base_token_info_address'),
        ('base_token_info_burn_status', 'burn_status'),
        ('base_token_info_burn_ratio', 'burn_ratio'),
        ('base_token_info_liquidity', 'liquidity'),
        ('address', 'base_token_info_pool_id'),
        ('creation_timestamp', 'base_token_info_creation_timestamp')
    ]
    
    for new_col, old_col in column_combinations:
        if new_col in df.columns and old_col in df.columns:
            df[new_col] = df[new_col].fillna(df[old_col])
            df.drop(columns=[old_col], inplace=True)
        elif new_col not in df.columns and old_col in df.columns:
            df[new_col] = df[old_col]
            df.drop(columns=[old_col], inplace=True)
    
    # Column renaming
    rename_map = {
        'address': 'pair_address',
        'base_address': 'address',
        'pool_type_str': 'platform',
        'base_token_info_symbol': 'symbol',
        'base_token_info_name': 'name',
        'base_token_info_logo': 'logo',
        'base_token_info_total_supply': 'total_supply',
        'base_token_info_holder_count': 'holder_count',
        'base_token_info_sniper_count': 'sniper_count',
        'base_token_info_price_change_percent1m': 'price_change_1m',
        'base_token_info_price_change_percent5m': 'price_change_5m',
        'base_token_info_price_change_percent1h': 'price_change_1h',
        'base_token_info_price': 'price',
        'base_token_info_is_show_alert': 'has_alert',
        'base_token_info_hot_level': 'hot_level',
        'base_token_info_liquidity': 'liquidity',
        'base_token_info_top_10_holder_rate': 'top_10_holder_rate',
        'base_token_info_renounced_mint': 'renounced_mint',
        'base_token_info_renounced_freeze_account': 'renounced_freeze_account',
        'base_token_info_social_links_twitter_username': 'twitter_username',
        'base_token_info_social_links_website': 'website',
        'base_token_info_social_links_telegram': 'telegram',
        'base_token_info_rug_ratio': 'rug_ratio',
        'base_token_info_is_wash_trading': 'is_wash_trading',
        'base_token_info_creator_balance_rate': 'creator_balance_rate',
        'base_token_info_rat_trader_amount_rate': 'rat_trader_amount_rate',
        'base_token_info_creator_token_status': 'creator_token_status',
        'base_token_info_bluechip_owner_percentage': 'bluechip_owner_percentage',
        'base_token_info_smart_degen_count': 'smart_degen_count',
        'base_token_info_renowned_count': 'renowned_count',
        'base_token_info_volume': 'volume',
        'base_token_info_swaps': 'swaps',
        'base_token_info_buys': 'buys',
        'base_token_info_sells': 'sells',
        'base_token_info_burn_status': 'burn_status',
        'base_token_info_burn_ratio': 'burn_ratio',
        'base_token_info_dev_token_burn_amount': 'dev_token_burn_amount',
        'base_token_info_dev_token_burn_ratio': 'dev_token_burn_ratio',
        'base_token_info_cto_flag': 'cto_flag',
        'base_token_info_twitter_change_flag': 'twitter_change_flag',
        'base_token_info_market_cap': 'market_cap',
        'base_token_info_creator_close': 'creator_close',
        'base_token_info_biggest_pool_address': 'biggest_pool_address'
    }
    
    existing_rename_map = {k: v for k, v in rename_map.items() if k in df.columns}
    df.rename(columns=existing_rename_map, inplace=True)

        # Timestamp conversion
    timestamp_cols = ['open_timestamp', 'creation_timestamp']
    for col in timestamp_cols:
        if col in df.columns:
            # First try UNIX timestamp, then string format
            try:
                df[col] = pd.to_datetime(df[col], unit='s', errors='coerce')
            except:
                df[col] = pd.to_datetime(df[col], errors='coerce')
    
    # Clean numeric columns
    numeric_cols = [
        'price', 'liquidity', 'volume', 'market_cap', 'quote_reserve',
        'initial_liquidity', 'initial_quote_reserve', 'total_supply',
        'holder_count', 'sniper_count', 'hot_level', 'top_10_holder_rate',
        'rug_ratio', 'rat_trader_amount_rate', 'bluechip_owner_percentage',
        'smart_degen_count', 'renowned_count', 'swaps', 'buys', 'sells',
        'buy_tax', 'sell_tax', 'dev_token_burn_amount', 'dev_token_burn_ratio', 'base_token_info_burn_ratio', 'burn_ratio',
        'cto_flag', 'twitter_change_flag', 'bot_degen_count', 'launchpad_status'
    ]
    df = clean_numeric_columns(df, numeric_cols)
    
    # Convert boolean columns
    bool_cols = [
        'has_alert', 'is_wash_trading', 'is_honypot', 'renounced',
        'renounced_mint', 'renounced_freeze_account', 'creator_close'
    ]
    bool_map = {
        'true': True, 'false': False,
        '1': True, '0': False,
        'yes': True, 'no': False,
        't': True, 'f': False
    }
    df = convert_boolean_columns(df, bool_cols, bool_map)
    
    # Ensure address is clean
    if 'address' in df.columns:
        df['address'] = df['address'].str.strip()
        df = df[df['address'].notna()]
    
    # Add status column with default
    df['status'] = 'alive'
    
    # Final cleanup - replace NaN/NaT with appropriate values
    df = df.replace({np.nan: None, pd.NaT: None})
    
    # Validate and handle missing values in required columns
    required_cols = ['address', 'status', 'symbol', 'platform']
    missing_cols = [col for col in required_cols if col not in df.columns]
    if missing_cols:
        raise ValueError(f"Missing required columns: {missing_cols}")
    
    for col in required_cols:
        if col in df.columns:
            if df[col].dtype == 'object':  # String/object columns
                df[col] = df[col].fillna("")
            elif df[col].dtype == 'bool':  # Boolean columns
                df[col] = df[col].fillna(False)
            else:  # Numeric columns
                df[col] = df[col].fillna(0)
    
    logging.info(f"Transformed DataFrame shape: {df.shape}")
    #logging.info(f"Columns in transformed DataFrame: {list(df.columns)}")
    
    return df

# df = transform_new_tokens(raw_data)
# pd.set_option('display.max_columns', None)  # Show all columns
# pd.set_option('display.max_rows', None)  # Show all rows

# print(df)
