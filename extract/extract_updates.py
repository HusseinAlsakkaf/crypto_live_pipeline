#extract_updates.py
import json
import time
import random
from datetime import datetime
import cloudscraper
from fake_useragent import UserAgent
import logging
from typing import List, Dict, Any
from concurrent.futures import ThreadPoolExecutor, as_completed
from utils.query_alive_tokens import get_alive_tokens

# Configuration
MAX_REQUESTS_PER_MINUTE = 30  # Conservative rate
BATCH_SIZE = 10  # Small batches
RETRY_DELAY = 10  # Base delay between retries
MAX_RETRIES = 3  # Max retries per batch
LOG_FILE = "updates_scraper.log"
PARALLEL_THREADS = 5  # Number of parallel threads

# Set up logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(LOG_FILE),
        logging.StreamHandler()
    ]
)

def create_scraper():
    """Create a new cloudscraper instance with proper configuration"""
    return cloudscraper.create_scraper(
        browser={
            'browser': 'chrome',
            'platform': 'windows',
            'mobile': False,
            'desktop': True,
        },
        delay=10,
        interpreter='native',
        captcha={
            'provider': '2captcha',  # Remove if not using
            'api_key': 'YOUR_2CAPTCHA_KEY'  # Add your key if using
        }
    )

def make_batch_request(scraper, addresses: List[str], attempt: int = 1) -> Dict[str, Any]:
    """Make API request with proper headers and payload"""
    headers = {
        "Accept": "application/json, text/plain, */*",
        "Content-Type": "application/json",
        "Origin": "https://gmgn.ai",
        "Referer": "https://gmgn.ai/sol/tokens",
        "User-Agent": UserAgent().random,
        "X-Requested-With": "XMLHttpRequest"
    }

    payload = {
        "chain": "sol",
        "addresses": addresses
    }

    try:
        # Random delay to mimic human behavior
        time.sleep(random.uniform(0.5, 1.5))

        response = scraper.post(
            "https://gmgn.ai/api/v1/mutil_window_token_info",
            json=payload,
            headers=headers,
            timeout=45
        )

        if response.status_code == 200:
            return {
                "success": True,
                "data": response.json(),
                "status": response.status_code
            }
        else:
            return {
                "success": False,
                "error": f"HTTP {response.status_code}",
                "response": response.text[:200],
                "status": response.status_code
            }

    except Exception as e:
        return {
            "success": False,
            "error": str(e),
            "status": None
        }

def process_batch(scraper, addresses: List[str]) -> List[Dict[str, Any]]:
    """Process a single batch with retries"""
    for attempt in range(1, MAX_RETRIES + 1):
        result = make_batch_request(scraper, addresses, attempt)

        if result["success"]:
            return result["data"]["data"]  # Return the actual token data

        logging.warning(f"Attempt {attempt} failed: {result.get('error')}")

        # Don't retry if it's a client error (4xx) except 429
        if result.get("status") and 400 <= result["status"] < 500 and result["status"] != 429:
            break

        if attempt < MAX_RETRIES:
            sleep_time = RETRY_DELAY * attempt + random.uniform(0, 3)
            logging.info(f"Waiting {sleep_time:.1f}s before retry...")
            time.sleep(sleep_time)

    return []  # Return empty list if all attempts failed

def main() -> List[Dict[str, Any]]:
    """Main processing loop"""
    # Initialize
    scraper = create_scraper()
    addresses = get_alive_tokens()

    if not addresses:
        logging.error("No token addresses found")
        return []

    results = []
    total_batches = (len(addresses) + BATCH_SIZE - 1) // BATCH_SIZE

    def process_single_batch(batch_num: int, batch: List[str]) -> List[Dict[str, Any]]:
        """Helper function to process a single batch"""
        logging.info(f"Processing batch {batch_num + 1}/{total_batches} ({len(batch)} tokens)")
        batch_data = process_batch(scraper, batch)
        if batch_data:
            logging.info(f"Added {len(batch_data)} items from batch")
            return [{"address": item["address"], "data": item} for item in batch_data if "address" in item]
        else:
            logging.warning(f"Batch {batch_num + 1} failed completely")
            return []

    # Parallel processing with ThreadPoolExecutor
    with ThreadPoolExecutor(max_workers=PARALLEL_THREADS) as executor:
        futures = []
        for batch_num in range(total_batches):
            start_idx = batch_num * BATCH_SIZE
            batch = addresses[start_idx:start_idx + BATCH_SIZE]
            futures.append(executor.submit(process_single_batch, batch_num, batch))

        # Collect results as they complete
        for future in as_completed(futures):
            try:
                results.extend(future.result())
            except Exception as e:
                logging.error(f"Error processing batch: {e}")

    logging.info(f"Completed with {len(results)} successful updates")
    return results

def save_results_to_file(results: List[Dict[str, Any]], filename: str = "scraped_results.json"):
    """Save the scraped results to a JSON file"""
    try:
        with open(filename, "w") as f:
            json.dump(results, f, indent=4)
        logging.info(f"Saved {len(results)} results to {filename}")
    except Exception as e:
        logging.error(f"Failed to save results to file: {e}")

def filter_irrelevant_tokens(results: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """Filter out irrelevant tokens based on specific criteria"""
    filtered_results = [
        result for result in results
        if result.get("data", {}).get("volume") > 0  # Example: Keep only tokens with non-zero volume
    ]
    logging.info(f"Filtered {len(filtered_results)} relevant tokens from {len(results)} total tokens")
    return filtered_results

def send_updates_to_api(filtered_results: List[Dict[str, Any]]):
    """Send filtered updates to an external API or database"""
    # Example: Send each token update to an API endpoint
    scraper = create_scraper()
    for token in filtered_results:
        try:
            response = scraper.post(
                "https://example.com/api/update_token",
                json=token["data"],
                timeout=30
            )
            if response.status_code == 200:
                logging.info(f"Successfully updated token: {token['address']}")
            else:
                logging.warning(f"Failed to update token {token['address']}: HTTP {response.status_code}")
        except Exception as e:
            logging.error(f"Error updating token {token['address']}: {e}")

if __name__ == "__main__":
    # Step 1: Scrape data
    scraped_data = main()

    # Step 2: Save results to file
    save_results_to_file(scraped_data)

    # Step 3: Filter irrelevant tokens
    filtered_data = filter_irrelevant_tokens(scraped_data)

    # Step 4: Send updates to an external API
    send_updates_to_api(filtered_data)