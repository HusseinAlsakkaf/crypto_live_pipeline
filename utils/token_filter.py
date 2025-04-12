#token_filter.py
import json
import os
from typing import List, Dict, Set
import logging
from utils.logging_utils import setup_logger

SEEN_TOKENS_FILE = "seen_base_addresses.json"
MAX_TRACKED_TOKENS = 2000
LOG_FILE = "scraper.log"

setup_logger(LOG_FILE)

class TokenFilter:
    def __init__(self):
        self.seen_base_addresses: Set[str] = set()
        self._load_addresses()

    def _load_addresses(self):
        """Load seen base addresses from the JSON file."""
        if os.path.exists(SEEN_TOKENS_FILE):
            try:
                with open(SEEN_TOKENS_FILE, 'r') as f:
                    loaded_data = json.load(f)
                    logging.debug(f"Loaded Data: {loaded_data}")
                    self.seen_base_addresses = set(loaded_data)
            except (json.JSONDecodeError, FileNotFoundError):
                logging.warning("Failed to load seen base addresses. Initializing an empty set.")
                self.seen_base_addresses = set()
        else:
            logging.info("Seen base addresses file does not exist. Initializing an empty set.")
            self.seen_base_addresses = set()

    def _save_addresses(self):
        """Save the latest seen base addresses to the JSON file."""
        try:
            with open(SEEN_TOKENS_FILE, 'w') as f:
                json.dump(list(self.seen_base_addresses)[-MAX_TRACKED_TOKENS:], f)
        except Exception as e:
            logging.error(f"Failed to save seen addresses: {str(e)}")

    def filter_new_tokens(self, token_data: List[Dict]) -> List[Dict]:
        """
        Filter tokens by base_address and return only new ones.
        Also deduplicates tokens within the current batch.
        """
        logging.debug(f"Token Data: {token_data}")
        if not isinstance(token_data, list):
            raise ValueError("token_data must be a list of tokens")

        new_tokens = []
        current_batch_addresses = set()  # To track unique addresses in the current batch
        
        for token in token_data:
            base_address = token.get('base_address')
            if base_address:
                base_address = base_address.strip().lower()  # Normalize
            else:
                logging.warning(f"Skipping token with missing or invalid base_address: {token}")
                continue

            # Skip duplicates within the current batch
            if base_address in current_batch_addresses:
                logging.debug(f"Skipping duplicate token with base_address: {base_address}")
                continue

            current_batch_addresses.add(base_address)

            # Check if the token is new (not seen before)
            if base_address not in self.seen_base_addresses:
                logging.debug(f"New Token Found: {token}")
                new_tokens.append(token)

        # Update tracking
        self.seen_base_addresses.update(current_batch_addresses)

        # Maintain size limit (FIFO)
        if len(self.seen_base_addresses) > MAX_TRACKED_TOKENS:
            self.seen_base_addresses = set(list(self.seen_base_addresses)[-MAX_TRACKED_TOKENS:])

        self._save_addresses()
        logging.info(f"Filtered {len(new_tokens)} new tokens from {len(token_data)} total tokens")
        logging.info(f"Total tracked tokens: {len(self.seen_base_addresses)}")
        return new_tokens

# Global instance
token_filter = TokenFilter()