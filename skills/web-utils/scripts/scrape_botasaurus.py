from botasaurus.browser import browser, Driver
import sys
import json


@browser(
    headless=False,
    reuse_driver=True,
    block_images_and_css=False,
    close_on_crash=True,
    max_retry=3,
)
def scrape(driver: Driver, url):
    """
    Scrapes the target URL using standard browser navigation.
    Note: Cloudflare bypass intentionally removed for legal/ethical compliance.
    """
    try:
        driver.get(url)
        driver.long_random_sleep()

        page_html = driver.page_html

        return {
            "url": url,
            "status": 200,
            "title": driver.title,
            "html": page_html,
        }
    except Exception as e:
        return {"error": str(e)}


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(json.dumps({"error": "No URL provided"}))
        sys.exit(1)

    url = sys.argv[1]

    try:
        result = scrape(url)
        print(json.dumps(result, default=str))
    except Exception as e:
        print(json.dumps({"error": str(e)}))
        sys.exit(1)
