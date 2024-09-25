import requests
from bs4 import BeautifulSoup
import os
import pandas as pd
import re
import logging
from time import sleep
from random import choice
import platform

# Set up logging
logging.basicConfig(filename="scraper.log", level=logging.INFO, format="%(asctime)s - %(message)s")

# List of common User-Agent headers to rotate through (to avoid being blocked)
user_agents = [
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.110 Safari/537.36",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_12_6) AppleWebKit/602.3.12 (KHTML, like Gecko) Version/10.1.2 Safari/603.3.8",
    "Mozilla/5.0 (iPhone; CPU iPhone OS 10_3 like Mac OS X) AppleWebKit/602.1.50 (KHTML, like Gecko) Version/10.0 Mobile/14E5239e Safari/602.1",
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:54.0) Gecko/20100101 Firefox/54.0",
]

# Function to scrape a single page
def scrape_page(url):
    # Use random User-Agent to avoid being blocked
    headers = {"User-Agent": choice(user_agents)}
    response = requests.get(url, headers=headers)

    # Lists to store scraped data
    product_names = []
    product_prices = []
    product_descriptions = []
    product_model_numbers = []
    image_urls = []

    # Check if the request was successful
    if response.status_code == 200:
        soup = BeautifulSoup(response.text, 'html.parser')

        # Use regex to find any class or id that may represent a product container
        product_containers = soup.find_all(True, {'class': re.compile(r'(product|item)', re.IGNORECASE)})

        if not product_containers:
            print("No products found on the page. Please check the HTML structure.")

        for product in product_containers:
            # Extract product name
            name = product.find(re.compile(r'h\d'), class_=re.compile(r'(name|title)', re.IGNORECASE))
            product_names.append(name.text.strip() if name else 'N/A')

            # Extract product price
            price = product.find('span', class_=re.compile(r'(price|amount)', re.IGNORECASE))
            product_prices.append(price.text.strip() if price else 'N/A')

            # Extract product description
            description = product.find('p', class_=re.compile(r'(description|detail)', re.IGNORECASE))
            product_descriptions.append(description.text.strip() if description else 'N/A')

            # Extract model number
            model = product.find('span', class_=re.compile(r'(model|sku)', re.IGNORECASE))
            product_model_numbers.append(model.text.strip() if model else 'N/A')

            # Extract image URL
            img = product.find('img', class_=re.compile(r'(image|img|photo)', re.IGNORECASE))
            img_url = img.get('src') if img else 'N/A'

            # Filter out base64-encoded images (data URLs)
            if img_url != 'N/A' and not img_url.startswith('data:image'):
                if not img_url.startswith('http'):
                    img_url = url + img_url
                image_urls.append(img_url)
            else:
                image_urls.append('N/A')

        return product_names, product_prices, product_descriptions, product_model_numbers, image_urls

    else:
        logging.error(f"Failed to retrieve content from {url}. Status code: {response.status_code}")
        return [], [], [], [], []

# Function to determine the desktop path based on OS
def get_desktop_path():
    if platform.system() == "Windows":
        return os.path.join(os.path.join(os.environ['USERPROFILE']), 'Desktop')
    else:
        return os.path.join(os.path.expanduser("~"), "Desktop")

# Ask the user to input the website URL
url = input("Please enter the website URL to scrape: ")

# Create a folder named "Website Data" on the Desktop
desktop_path = get_desktop_path()
data_folder = os.path.join(desktop_path, "Website Data")

if not os.path.exists(data_folder):
    os.makedirs(data_folder)

# Generate a folder name based on the website URL (use domain name)
website_name = url.split("//")[-1].split("/")[0]  # Extract the domain name
website_folder_path = os.path.join(data_folder, website_name)

# Create a folder for the individual website
if not os.path.exists(website_folder_path):
    os.makedirs(website_folder_path)

# Pagination support
page = 1
all_product_names = []
all_product_prices = []
all_product_descriptions = []
all_product_model_numbers = []
all_image_urls = []

while True:
    paginated_url = f"{url}?page={page}"
    logging.info(f"Scraping page {page} - {paginated_url}")

    names, prices, descriptions, models, images = scrape_page(paginated_url)

    if not names:  # If no products are found on the current page, exit the loop
        print(f"Completed scraping. Total pages scraped: {page - 1}")
        break

    # Append current page data to global lists
    all_product_names.extend(names)
    all_product_prices.extend(prices)
    all_product_descriptions.extend(descriptions)
    all_product_model_numbers.extend(models)
    all_image_urls.extend(images)

    # Progress display
    print(f"Page {page} scraped. {len(names)} products found.")
    logging.info(f"Page {page} scraped. {len(names)} products found.")

    # Wait between requests to avoid overloading the server
    sleep(2)  # Pause for 2 seconds between requests

    # Move to the next page
    page += 1

# Prepare data for export to Excel
data = {
    'Product Name': all_product_names if all_product_names else ['N/A'],
    'Price': all_product_prices if all_product_prices else ['N/A'],
    'Description': all_product_descriptions if all_product_descriptions else ['N/A'],
    'Model Number': all_product_model_numbers if all_product_model_numbers else ['N/A'],
    'Image URLs': all_image_urls if all_image_urls else ['N/A'],
}

# Convert to a DataFrame
df = pd.DataFrame(data)

# Save the Excel file in the website's folder
output_file = os.path.join(website_folder_path, 'scraped_product_data.xlsx')
df.to_excel(output_file, index=False)

print(f"\nProduct data successfully exported to {output_file}")
