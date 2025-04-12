import os
from dotenv import load_dotenv
from sqlalchemy import create_engine

# Load environment variables
load_dotenv()

# Global variable to store the engine instance
_ENGINE = None

def get_db_engine():
    """
    Create and return a SQLAlchemy database engine with connection pooling.
    The engine is cached to avoid redundant initialization.
    """
    global _ENGINE
    if _ENGINE is None:
        # Validate required environment variables
        required_vars = ['DB_USER', 'DB_PASSWORD', 'DB_HOST', 'DB_PORT', 'DB_NAME']
        missing_vars = [var for var in required_vars if not os.getenv(var)]
        if missing_vars:
            raise ValueError(f"Missing environment variables: {', '.join(missing_vars)}")
        
        # Build the database URL
        db_url = f"postgresql://{os.getenv('DB_USER')}:{os.getenv('DB_PASSWORD')}@{os.getenv('DB_HOST')}:{os.getenv('DB_PORT')}/{os.getenv('DB_NAME')}"
        
        # Create the engine with connection pooling
        _ENGINE = create_engine(db_url, pool_size=5, max_overflow=10)
    
    return _ENGINE