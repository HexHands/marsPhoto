Rails.application.config.after_initialize do
  next unless ENV["AUTO_SCRAPE"] == "true"

  # Run automatic scraping in a background thread.
  # Use WEB_CONCURRENCY=1 on Render to avoid duplicate scrapers.
  Thread.new do
    loop do
      scrapers = {
        "Perseverance" => PerseveranceScraper,
        "Curiosity" => CuriosityScraper
      }

      scrapers.each do |roverName, scraperClass|
        begin
          scraperClass.new.scrape
        rescue StandardError => error
          Rails.logger.error(
            "AUTO_SCRAPE #{roverName} error: #{error.class}: #{error.message}"
          )
        end
      end

      sleepSeconds = ENV.fetch(
        "SCRAPE_LOOP_SLEEP_SECONDS", "30"
      ).to_i

      sleep [sleepSeconds, 1].max
    end
  end
end
