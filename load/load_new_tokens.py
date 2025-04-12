from utils.database import get_db_engine
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy import Table, MetaData, inspect
import pandas as pd
import logging
import numpy as np

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def validate_columns(engine):
    """Check which columns exist in the database table"""
    insp = inspect(engine)
    db_columns = insp.get_columns('tokens')
    return [col['name'] for col in db_columns]

def validate_numeric_columns(df, numeric_cols):
    """
    Validate numeric columns to ensure they contain valid values.
    Logs and raises an error if invalid values are found.
    """
    for col in numeric_cols:
        if col in df.columns:
            # Check for invalid values (empty strings or non-numeric strings)
            invalid_values = df[df[col].apply(lambda x: isinstance(x, str) and x.strip() == "")][col]
            if not invalid_values.empty:
                logger.error(f"Column '{col}' contains invalid values: {invalid_values.tolist()}")
                raise ValueError(f"Column '{col}' contains invalid values.")

def batch_upsert(engine, data: list, batch_size: int = 50):
    """Safe batch upsert with column validation"""
    valid_columns = validate_columns(engine)
    filtered_data = [
        {k: v for k, v in record.items() if k in valid_columns}
        for record in data
    ]

    metadata = MetaData()
    tokens_table = Table('tokens', metadata, autoload_with=engine)

    stmt = insert(tokens_table).values(filtered_data)
    update_cols = {c.name: stmt.excluded[c.name] for c in tokens_table.columns if c.name != 'address'}

    upsert = stmt.on_conflict_do_update(
        index_elements=['address'],
        set_=update_cols
    )

    with engine.begin() as conn:
        for i in range(0, len(filtered_data), batch_size):
            batch = filtered_data[i:i + batch_size]
            try:
                conn.execute(upsert, batch)
                logger.info(f"Inserted batch {i//batch_size + 1}")
            except Exception as e:
                logger.error(f"Batch {i//batch_size + 1} failed: {str(e)}")
                raise

def load_data(df):
    """Main load function with proper error handling"""
    # Log the transformed DataFrame for debugging
    logging.info("╔════════════════════════════════════════════╗")
    logging.info("║             LOADING PHASE                  ║")
    logging.info("╚════════════════════════════════════════════╝\n")
    logger.debug(df.head().to_dict(orient='records'))
    
    # List of numeric columns to validate
    numeric_cols = [
        'price', 'liquidity', 'market_cap', 'volume', 'total_supply', 'holder_count',
        'burn_ratio', 'top_10_holder_rate', 'rug_ratio', 'creator_balance_rate',
        'rat_trader_amount_rate', 'bluechip_owner_percentage', 'swaps', 'buys', 'sells',
        'dev_token_burn_amount', 'dev_token_burn_ratio', 'price_change_1m', 'price_change_5m', 'price_change_1h'
    ]
    
    # Validate numeric columns
    validate_numeric_columns(df, numeric_cols)
    
    # Replace NaN with None
    data = df.replace({np.nan: None}).to_dict('records')
    
    # Get database engine
    engine = get_db_engine()
    
    try:
        batch_upsert(engine, data)
        logger.info(f"Successfully loaded {len(data)} records")
    except Exception as e:
        logger.error(f"Load failed: {str(e)}")
        raise