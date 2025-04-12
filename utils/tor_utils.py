import time
import requests
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
    def __init__(self, password):
        self.password = password
        self.current_ip = None

    def renew_connection(self):
        try:
            with Controller.from_port(port=9051) as controller:
                controller.authenticate(password=self.password)
                controller.signal(Signal.NEWNYM)
                #logging.info("Successfully renewed Tor circuit")
                time.sleep(5)  # Wait for new circuit to establish
                #self.current_ip = self.get_current_ip()  # Update the current IP
                return True
        except Exception as e:
            logging.error(f"Tor renewal failed: {str(e)}")
            return False

    # def get_current_ip(self):
    #     """Check current Tor exit node IP"""
    #     try:
    #         response = requests.get(
    #             "https://api.ipify.org?format=json",
    #             proxies=TOR_PROXY,
    #             timeout=10
    #         )
    #         return response.json().get('ip', 'Unknown')
    #     except Exception as e:
    #         logging.error(f"IP check failed: {str(e)}")
    #         return "Unknown"