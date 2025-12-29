# lib/scraper_helpers.rb
module ScraperHelpers
  # call the existing create_photo and then sleep
  def create_photo_sleep(image)
    create_photo(image) # this calls the scraper's original method:contentReference[oaicite:0]{index=0}
    sleep 1             # throttle to one photo per second
  end

  # optional: a slow version of the scrape loop that uses create_photo_sleep
  def scrape_slowly
    collect_links.each do |url|
      begin
        response = JSON.parse(URI.open(url).read)
        # each scraper’s JSON structure is a bit different; adapt this line accordingly
        images = response['images'] || response['items']
        images.each do |image|
          # reuse the scraper’s own condition for “full” images, if it has one
          if !image['sample_type'] || image['sample_type'] == 'Full'
            create_photo_sleep(image)
          end
        end
      rescue => e
        Rails.logger.warn "Error scraping #{url}: #{e.message}"
      end
    end
  end
end
