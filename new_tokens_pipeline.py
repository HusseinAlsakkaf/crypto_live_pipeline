import time
import random
import logging
import os
from dotenv import load_dotenv
from utils.tor_utils import TorController
from extract.extract_new_tokens import make_request
from transform.transform_new_tokens import transform_new_tokens
from load.load_new_tokens import load_data

# Configure logging
logging.basicConfig(level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s")
logger = logging.getLogger(__name__)

# Load environment variables
load_dotenv()

# Initialize TorController
TOR_PASSWORD = os.getenv("TOR_PASSWORD")  # Ensure this is set in your .env file
tor_controller = TorController(password=TOR_PASSWORD)

def verify_tor_connection():
    """Verify Tor is working before starting pipeline."""
    logger.info("Verifying Tor connection...")
    if not tor_controller.renew_connection():
        raise ConnectionError("Failed to establish initial Tor connection")
    #logger.info(f"Initial Tor IP: {tor_controller.current_ip}")

def extract_new_tokens():
    """Extract new tokens using the Tor-enabled request."""
    logger.info("Extracting new tokens...")
    raw_data = make_request()
    if not raw_data:
        logger.warning("No new tokens found.")
    return raw_data

def transform_and_load_new_tokens(raw_data):
    """Transform and load new tokens."""
    if raw_data:
        logger.info("Transforming new tokens...")
        df = transform_new_tokens(raw_data)
        logger.info("Loading new tokens...")
        load_data(df)

def run_pipeline():
    """Orchestrates the ETL pipeline for new tokens."""
    verify_tor_connection()
    
    while True:

        loop_start_time = time.time()  # Capture start time

        try:
            logging.info("\n")
            logging.info("  ✧･ﾟ: *✧･ﾟ:*  STARTING NEW LOOP  *:･ﾟ✧*:･ﾟ✧")
            logging.info("  ☆.。.:*・°☆.。.:*・°☆.。.:*・°☆.。.:*")
            logging.info("\n")
            # Extract new tokens
            raw_data = extract_new_tokens()
            
            # Transform and load new tokens
            transform_and_load_new_tokens(raw_data)
            
            # Random delay between cycles
            logger.info("Sleeping for next cycle...")
            time.sleep(random.uniform(5, 15))

            loop_duration = time.time() - loop_start_time

            logging.info("\n")
            logging.info("  ✧･ﾟ: *✧･ﾟ:*  LOOP COMPLETED IN {:.2f}s  *:･ﾟ✧*:･ﾟ✧".format(loop_duration))
            logging.info("  ☆.。.:*・°☆.。.:*・°☆.。.:*・°☆.。.:*・°☆")
            logging.info("  ✦･ﾟ✧･ﾟ✦  Ready for next adventure! ✦･ﾟ✧･ﾟ✦")
            logging.info("\n")
            
        except KeyboardInterrupt:
            logger.info("Pipeline stopped by user")
            break
        except Exception as e:
            logger.error(f"Error in pipeline: {str(e)}", exc_info=True)
            # Attempt to renew Tor connection on error
            tor_controller.renew_connection()
            time.sleep(10)

if __name__ == "__main__":
    run_pipeline()