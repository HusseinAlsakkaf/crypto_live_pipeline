import random
from datetime import datetime
import logging
from utils.token_filter import token_filter
from utils.scraper_utils import create_scraper
from utils.logging_utils import setup_logger
from utils.retry_utils import retry_request
from concurrent.futures import ThreadPoolExecutor, as_completed
from utils.tor_utils import TorController
import time


# Configuration
# MAX_REQUESTS_PER_MINUTE = 200
# REQUEST_DELAY = 60 / MAX_REQUESTS_PER_MINUTE
TOR_PROXY = {
    "http": "socks5://127.0.0.1:9050",
    "https": "socks5://127.0.0.1:9050"
}

LOG_FILE = "scraper.log"
TOR_PASSWORD = "tor_poor"  # Change this to your Tor password

# Set up logging
setup_logger(LOG_FILE)


# Initialize Tor controller
tor_controller = TorController(TOR_PASSWORD)

# Initialize tools
try:
    from fake_useragent import UserAgent
    ua = UserAgent(
        fallback='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36',
        cache=True,
        path='/home/ec2-user/.fake-useragent/cache.json'
    )
except Exception as e:
    print(f"UserAgent init error: {e}")
    from utils.useragent import DEFAULT_AGENTS, get_random_agent
    class FallbackUserAgent:
        @property
        def random(self):
            return get_random_agent()
        
        @property
        def chrome(self):
            return DEFAULT_AGENTS['chrome']
            
        @property
        def firefox(self):
            return DEFAULT_AGENTS['firefox']
    
    ua = FallbackUserAgent()
# set up scraper
scraper = create_scraper()

#set up tor
tor_controller = TorController(TOR_PASSWORD)


def make_http_request():
    """Make the actual HTTP request."""
    tor_controller.renew_connection()  # Rotate Tor IP
    #logging.info(f"Using Tor IP: {tor_controller.current_ip}")

    headers = {
        "Accept": "application/json, text/plain, */*",
        "Content-Type": "application/json",
        "Referer": "https://gmgn.ai/sol/tokens/new",
        "User-Agent": ua.random,
        "Origin": "https://gmgn.ai",
        "Accept-Language": "en-US,en;q=0.9",
        "Connection": "keep-alive",
        "Sec-Fetch-Dest": "empty",
        "Sec-Fetch-Mode": "cors",
        "Sec-Fetch-Site": "same-origin",
        "Pragma": "no-cache",
        "Cache-Control": "no-cache"
    }
    
    params = {
        "device_id": f"d66bea1d-c864-4955-adba-{''.join(random.choices('0123456789abcdef', k=12))}",
        "client_id": f"gmgn_web_{datetime.now().strftime('%Y.%m%d.%H%M%S')}",
        "from_app": "gmgn",
        "app_ver": datetime.now().strftime('%Y.%m%d.%H%M%S'),
        "tz_name": random.choice(["Europe/London", "America/New_York", "Asia/Tokyo"]),
        "tz_offset": str(random.randint(-12, 12)),
        "app_lang": random.choice(["en-US", "en-GB", "fr-FR"]),
        "limit": "100",
        "orderby": "open_timestamp",
        "direction": "desc",
        "period": "5m"
    }

    try:
        response = scraper.get(
            "https://gmgn.ai/defi/quotation/v1/pairs/sol/new_pairs/5m",
            params=params,
            headers=headers,
            proxies=TOR_PROXY,
            timeout=30
        )
        
        logging.info(f"HTTP Status Code: {response.status_code}")
        
        if response.status_code == 403:
            logging.warning("Received 403 Forbidden")
            make_http_request.last_success = False
            return {"success": False, "should_retry": True}
        
        if response.status_code != 200:
            logging.error(f"Non-200 response: {response.status_code}")
            make_http_request.last_success = False
            return {"success": False, "should_retry": False}
        
        make_http_request.last_success = True
        return {
            "success": True,
            "data": response.json()
        }
        
    except Exception as e:
        logging.error(f"Request failed: {str(e)}")
        make_http_request.last_success = False
        return {"success": False, "should_retry": True}

def make_parallel_requests(num_requests=5):
    """Fetch raw data in parallel (NO FILTERING YET)"""
    raw_results = []
    with ThreadPoolExecutor(max_workers=num_requests) as executor:
        futures = [executor.submit(make_http_request) for _ in range(num_requests)]
        for future in as_completed(futures):
            result = future.result()
            if result and result.get("success"):
                json_data = result["data"]
                if isinstance(json_data, dict) and 'data' in json_data:
                    raw_results.extend(json_data['data']['pairs'])  # Combine raw data
    return raw_results

def make_request():
    """1. Fetch raw data in parallel → 2. Filter combined results"""
    logging.info("╔════════════════════════════════════════════╗")
    logging.info("║               EXTRACTION  PHASE            ║")
    logging.info("╚════════════════════════════════════════════╝\n")
    try:
        # Step 1: Get ALL raw tokens from parallel requests
        all_raw_tokens = make_parallel_requests(num_requests=5)
        if not all_raw_tokens:
            return None
        logging.info(f"raw tokens: {len(all_raw_tokens)}")

        # Step 2: Filter COMBINED results in one atomic operation
        filtered_tokens = token_filter.filter_new_tokens(all_raw_tokens)  # Thread-safe filtering

        logging.info(f"filtered tokens: {len(filtered_tokens)}")
        
        return {
            'code': 0,
            'msg': 'success',
            'data': {'pairs': filtered_tokens}
        }
    except Exception as e:
        logging.error(f"Request failed: {str(e)}")
        return None


