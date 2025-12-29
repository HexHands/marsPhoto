Rails.application.config.after_initialize do
  next unless ENV["AUTO_SCRAPE"] == "true"

  # Avoid spawning multiple scrapers if Puma uses multiple workers
  # Easiest is: set WEB_CONCURRENCY=1 in Render
  Thread.new do
    loop do
      begin
        PerseveranceScraper.new.scrape
        CuriosityScraper.new.scrape
        OpportunitySpiritScraper.new("Opportunity").scrape
        OpportunitySpiritScraper.new("Spirit").scrape
      rescue => e
        Rails.logger.error("AUTO_SCRAPE error: #{e.class}: #{e.message}")
      ensure
        sleep ENV.fetch("SCRAPE_LOOP_SLEEP_SECONDS", "30").to_i
      end
    end
  end
end
