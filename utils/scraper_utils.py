# utils/scraper_utils.py
import cloudscraper
import os

def create_scraper():
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
            'provider': '2captcha',  # Optional
            'api_key': os.getenv('CAPTCHA_API_KEY', '')
        }
    )