import os
import platform
import pandas as pd
import scrapy
from scrapy.crawler import CrawlerProcess
from scrapy.utils.project import get_project_settings

# Function to determine the Documents path based on OS
def get_documents_path():
    if platform.system() == "Windows":
        return os.path.join(os.path.join(os.environ['USERPROFILE']), 'Documents')
    else:
        return os.path.join(os.path.expanduser("~"), "Documents")

class ProductSpider(scrapy.Spider):
    name = "products"

    def __init__(self, url=None, *args, **kwargs):
        super(ProductSpider, self).__init__(*args, **kwargs)
        self.start_urls = [url]
        self.page = 1
        self.all_data = {
            'Product Name': [],
            'Price': [],
            'Description': [],
            'Model Number': [],
            'Image URLs': [],
        }

    def parse(self, response):
        product_containers = response.xpath("//*[contains(@class, 'product') or contains(@class, 'item')]")
        
        if not product_containers:
            self.log("No products found. Ending scrape.")
            self.save_data()
            return

        for product in product_containers:
            name = product.xpath(".//h2[contains(@class, 'name') or contains(@class, 'title')]/text()").get(default='N/A').strip()
            price = product.xpath(".//span[contains(@class, 'price') or contains(@class, 'amount')]/text()").get(default='N/A').strip()
            description = product.xpath(".//p[contains(@class, 'description') or contains(@class, 'detail')]/text()").get(default='N/A').strip()
            model = product.xpath(".//span[contains(@class, 'model') or contains(@class, 'sku')]/text()").get(default='N/A').strip()
            image_url = product.xpath(".//img[contains(@class, 'image') or contains(@class, 'img')]/@src").get(default='N/A')
            
            # Handle image URL
            if image_url and not image_url.startswith('http'):
                image_url = response.urljoin(image_url)

            # Append data to respective lists
            self.all_data['Product Name'].append(name)
            self.all_data['Price'].append(price)
            self.all_data['Description'].append(description)
            self.all_data['Model Number'].append(model)
            self.all_data['Image URLs'].append(image_url)

        # Proceed to next page if pagination exists
        next_page = response.xpath("//a[contains(@class, 'next')]/@href").get()
        if next_page:
            next_page_url = response.urljoin(next_page)
            self.page += 1
            yield scrapy.Request(next_page_url, callback=self.parse)
        else:
            self.log(f"Scraping completed. {self.page} pages scraped.")
            self.save_data()

    def save_data(self):
        # Save data to an Excel file
        documents_path = get_documents_path()
        data_folder = os.path.join(documents_path, "Website Data")
        
        if not os.path.exists(data_folder):
            os.makedirs(data_folder)

        website_name = self.start_urls[0].split("//")[-1].split("/")[0]  # Extract the domain name
        website_folder_path = os.path.join(data_folder, website_name)

        if not os.path.exists(website_folder_path):
            os.makedirs(website_folder_path)

        output_file = os.path.join(website_folder_path, 'scraped_product_data.xlsx')
        df = pd.DataFrame(self.all_data)
        df.to_excel(output_file, index=False)
        self.log(f"Data successfully saved to {output_file}")

def run_scrapy(url):
    process = CrawlerProcess(settings=get_project_settings())
    process.crawl(ProductSpider, url=url)
    process.start()

if __name__ == "__main__":
    # Ask for the URL
    url = input("Please enter the website URL to scrape: ")
    run_scrapy(url)
