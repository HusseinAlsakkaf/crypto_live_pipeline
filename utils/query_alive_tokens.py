# query_alive_tokens.py
import os
from sqlalchemy import create_engine, text
from dotenv import load_dotenv
import logging
from typing import List
import time

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def create_conn():
    """Create database engine with connection pooling"""
    load_dotenv()
    db_url = f"postgresql://{os.getenv('DB_USER')}:{os.getenv('DB_PASSWORD')}@{os.getenv('DB_HOST')}:{os.getenv('DB_PORT')}/{os.getenv('DB_NAME')}"
    return create_engine(db_url, pool_size=5, max_overflow=10)

# Global variable to track the last time frozen tokens were fetched
LAST_FROZEN_FETCH_TIME = None

def get_alive_tokens(batch_size: int = 1000) -> List[str]:
    """
    Query the database for tokens with status 'alive' or 'alive + frozen' based on timing.
    
    Args:
        batch_size: Number of records to fetch at a time (for memory efficiency)
        
    Returns:
        List of token addresses
    """
    global LAST_FROZEN_FETCH_TIME
    
    # Determine whether to include frozen tokens (every 12 hours)
    current_time = time.time()
    if LAST_FROZEN_FETCH_TIME is None:
        LAST_FROZEN_FETCH_TIME = current_time  # Initialize on first run
    elapsed_time = current_time - LAST_FROZEN_FETCH_TIME
    
    include_frozen = False
    if elapsed_time >= 12 * 60 * 60:  # 12 hours in seconds
        include_frozen = True
        LAST_FROZEN_FETCH_TIME = current_time  # Reset timer
    
    engine = create_conn()
    addresses = []
    
    try:
        with engine.connect() as conn:
            offset = 0
            while True:
                # Modify query to include frozen tokens conditionally
                query = text("""
                    SELECT address 
                    FROM tokens 
                    WHERE status IN :statuses
                    ORDER BY creation_timestamp DESC
                    LIMIT :limit OFFSET :offset
                """)
                
                statuses = ('alive', 'frozen') if include_frozen else ('alive',)
                result = conn.execute(query, {'statuses': statuses, 'limit': batch_size, 'offset': offset})
                batch = [row[0] for row in result]
                
                if not batch:
                    break
                    
                addresses.extend(batch)
                offset += batch_size
                
                logger.info(f"Fetched {len(batch)} addresses (total: {len(addresses)})")
                
        logger.info(f"Total {'alive + frozen' if include_frozen else 'alive'} tokens found: {len(addresses)}")
        return addresses
        
    except Exception as e:
        logger.error(f"Error querying tokens: {str(e)}")
        raise
    finally:
        engine.dispose()

if __name__ == "__main__":
    # Example usage
    alive_tokens = get_alive_tokens()
    print(f"First 5 alive tokens: {alive_tokens[:5]}")
    print(f"Total alive tokens: {len(alive_tokens)}")