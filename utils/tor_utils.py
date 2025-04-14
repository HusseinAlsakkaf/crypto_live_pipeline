import time
import logging
from stem import Signal
from stem.control import Controller
import logging 

logging.getLogger('stem').setLevel(logging.WARNING)

# Configuration
TOR_PROXY = {
    "http": "socks5://127.0.0.1:9050",
    "https": "socks5://127.0.0.1:9050"
}


class TorController:
    def __init__(self):
        self.current_ip = None

    def renew_connection(self):
        try:
            with Controller.from_port(port=9051) as controller:
                # Use cookie authentication
                controller.authenticate()
                controller.signal(Signal.NEWNYM)
                time.sleep(5)  # Wait for new circuit to establish
                return True
        except Exception as e:
            logging.error(f"Tor renewal failed: {str(e)}")
            return False