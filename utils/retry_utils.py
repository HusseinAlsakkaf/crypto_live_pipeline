# utils/retry_utils.py
import time
import random
import logging

def retry_request(func, max_retries=3, base_delay=10):
    for attempt in range(1, max_retries + 1):
        try:
            result = func()
            if result.get("success"):
                return result
        except Exception as e:
            logging.warning(f"Attempt {attempt} failed: {str(e)}")
        sleep_time = base_delay * attempt + random.uniform(0, 3)
        logging.info(f"Waiting {sleep_time:.1f}s before retry...")
        time.sleep(sleep_time)
    return {"success": False, "error": "Max retries exceeded"}