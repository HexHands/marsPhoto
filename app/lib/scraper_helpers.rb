# app/lib/scraper_helpers.rb
module ScraperHelpers
  private

  def scrape_sleep_seconds
    ENV.fetch("SCRAPE_SLEEP_SECONDS", "1").to_f
  end

  # Wrap the *parent* create_photo and then sleep
  def create_photo_sleep(image)
    super(image)
    sleep(scrape_sleep_seconds) if scrape_sleep_seconds > 0
  end
end
