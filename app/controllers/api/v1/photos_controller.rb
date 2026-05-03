class Api::V1::PhotosController < ApplicationController
  DEFAULT_PER_PAGE = 25
  MAX_PER_PAGE = 100
  MAX_PAGE_NUMBER = 100_000
  MAX_SOL_VALUE = 1_000_000_000

  COUNT_CACHE_SECONDS = 24.hours
  COUNT_RATE_LIMIT = 60
  COUNT_RATE_WINDOW = 60

  @@countRequests = {}

  def index
    if countMetadataRequested?
      renderCountMetadata
    else
      renderPhotos
    end
  rescue ArgumentError => error
    render json: { error: error.message }, status: :bad_request
  rescue StandardError => error
    Rails.logger.error("PhotosController error: #{error.class}: #{error.message}")
    render json: { error: "Internal server error" }, status: :internal_server_error
  end

  private

  ##################################################
  # Normal photo response
  ##################################################

  def renderPhotos
    pageNumber = boundedIntegerParam(firstPresentParam(:page), 1, 1, MAX_PAGE_NUMBER, "page")
    perPage = boundedIntegerParam(firstPresentParam(:perPage, :per_page), DEFAULT_PER_PAGE, 1, MAX_PER_PAGE, "perPage")

    photoScope = filteredPhotosScope
    photoScope = photoScope.includes(:camera, :rover)
    photoScope = photoScope.order(:id).offset((pageNumber - 1) * perPage).limit(perPage)

    expires_in 4.hours, public: true

    render json: {
      photos: photoScope.map { |photo| photoJson(photo) }
    }
  end

  ##################################################
  # Lightweight generic count metadata
  #
  # Examples:
  # /api/v1/photos?metadata=count&solStart=100&solEnd=199
  # /api/v1/photos?metadata=count&solStart=1200
  #
  # This intentionally does NOT return sitemap URLs, priorities, or page lists.
  ##################################################

  def renderCountMetadata
    unless countRateLimitAllowed?
      response.headers["Retry-After"] = COUNT_RATE_WINDOW.to_s
      return render json: { error: "Too many count requests. Please retry later." }, status: :too_many_requests
    end

    solStart = requiredIntegerParam(firstPresentParam(:solStart, :start_sol), "solStart", 0, MAX_SOL_VALUE)
    solEndRaw = firstPresentParam(:solEnd, :end_sol)
    solEnd = solEndRaw.present? ? boundedIntegerParam(solEndRaw, nil, solStart, MAX_SOL_VALUE, "solEnd") : nil

    photoScope = filteredPhotosScope(solStart, solEnd)

    cacheKey = countCacheKey(solStart, solEnd)

    photoCount = Rails.cache.fetch(cacheKey, expires_in: COUNT_CACHE_SECONDS) do
      photoScope.count
    end

    expires_in COUNT_CACHE_SECONDS, public: true
    response.headers["X-Content-Type-Options"] = "nosniff"

    render json: {
      metadata: "count",
      solStart: solStart,
      solEnd: solEnd,
      openEnded: solEnd.nil?,
      photoCount: photoCount,
      hasPhotos: photoCount > 0,
      generatedAt: Time.now.utc.iso8601,
      cachedForSeconds: COUNT_CACHE_SECONDS.to_i
    }
  end

  def countMetadataRequested?
    params[:metadata].to_s.downcase == "count"
  end

  ##################################################
  # Query building
  ##################################################

  def filteredPhotosScope(solStartOverride = nil, solEndOverride = nil)
    photoScope = Photo.all

    roverValue = firstPresentParam(:rover, :roverName, :rover_name, :rover_id)
    if roverValue.present?
      roverText = roverValue.to_s.strip

      if roverText.match?(/\A\d+\z/)
        photoScope = photoScope.where(rover_id: roverText.to_i)
      else
        photoScope = photoScope.joins(:rover).where("LOWER(rovers.name) = ?", roverText.downcase)
      end
    end

    cameraValue = firstPresentParam(:camera, :cameraName, :camera_name)
    if cameraValue.present?
      cameraText = cameraValue.to_s.strip.downcase
      photoScope = photoScope.joins(:camera).where(
        "LOWER(cameras.name) = ? OR LOWER(cameras.full_name) = ?",
        cameraText,
        cameraText
      )
    end

    earthDateValue = firstPresentParam(:earthDate, :earth_date)
    if earthDateValue.present?
      photoScope = photoScope.where(earth_date: earthDateValue.to_s.strip)
    end

    solValue = firstPresentParam(:sol)
    if solValue.present?
      solNumber = requiredIntegerParam(solValue, "sol", 0, MAX_SOL_VALUE)
      return photoScope.where(sol: solNumber)
    end

    solStart = solStartOverride
    solEnd = solEndOverride

    if solStart.nil?
      solStartRaw = firstPresentParam(:solStart, :start_sol)
      solStart = solStartRaw.present? ? boundedIntegerParam(solStartRaw, nil, 0, MAX_SOL_VALUE, "solStart") : nil
    end

    if solEnd.nil?
      solEndRaw = firstPresentParam(:solEnd, :end_sol)
      solEnd = solEndRaw.present? ? boundedIntegerParam(solEndRaw, nil, 0, MAX_SOL_VALUE, "solEnd") : nil
    end

    if solStart.present? && solEnd.present?
      if solEnd < solStart
        raise ArgumentError, "solEnd must be greater than or equal to solStart."
      end

      photoScope = photoScope.where(sol: solStart..solEnd)
    elsif solStart.present?
      photoScope = photoScope.where("photos.sol >= ?", solStart)
    elsif solEnd.present?
      photoScope = photoScope.where("photos.sol <= ?", solEnd)
    end

    photoScope
  end

  ##################################################
  # JSON formatting
  ##################################################

  def photoJson(photo)
    {
      id: photo.id,
      sol: photo.sol,
      camera: cameraJson(photo.camera),
      img_src: photo.img_src,
      earth_date: photo.earth_date,
      rover: roverJson(photo.rover)
    }
  end

  def cameraJson(camera)
    return nil if camera.nil?

    {
      id: camera.id,
      name: camera.name,
      rover_id: camera.rover_id,
      full_name: camera.full_name
    }
  end

  def roverJson(rover)
    return nil if rover.nil?

    {
      id: rover.id,
      name: rover.name,
      landing_date: rover.landing_date,
      launch_date: rover.launch_date,
      status: rover.status
    }
  end

  ##################################################
  # Input helpers
  ##################################################

  def firstPresentParam(*paramNames)
    paramNames.each do |paramName|
      value = params[paramName]
      return value if value.present?
    end

    nil
  end

  def requiredIntegerParam(rawValue, fieldName, minValue, maxValue)
    if rawValue.blank?
      raise ArgumentError, "#{fieldName} is required."
    end

    boundedIntegerParam(rawValue, nil, minValue, maxValue, fieldName)
  end

  def boundedIntegerParam(rawValue, defaultValue, minValue, maxValue, fieldName)
    value = if rawValue.present?
      parseInteger(rawValue, fieldName)
    else
      defaultValue
    end

    return value if value.nil?

    if value < minValue || value > maxValue
      raise ArgumentError, "#{fieldName} must be between #{minValue} and #{maxValue}."
    end

    value
  end

  def parseInteger(rawValue, fieldName)
    valueText = rawValue.to_s.strip

    unless valueText.match?(/\A\d+\z/)
      raise ArgumentError, "#{fieldName} must be a whole number."
    end

    valueText.to_i
  end

  ##################################################
  # Caching and simple protection
  ##################################################

  def countCacheKey(solStart, solEnd)
    roverValue = firstPresentParam(:rover, :roverName, :rover_name, :rover_id).to_s.strip.downcase
    cameraValue = firstPresentParam(:camera, :cameraName, :camera_name).to_s.strip.downcase
    earthDateValue = firstPresentParam(:earthDate, :earth_date).to_s.strip

    [
      "photo-count-v1",
      "solStart:#{solStart}",
      "solEnd:#{solEnd || 'open'}",
      "rover:#{roverValue}",
      "camera:#{cameraValue}",
      "earthDate:#{earthDateValue}"
    ].join("/")
  end

  def countRateLimitAllowed?
    clientKey = request.remote_ip.to_s
    now = Time.now.to_i
    windowStart = now - COUNT_RATE_WINDOW

    @@countRequests[clientKey] ||= []
    @@countRequests[clientKey] = @@countRequests[clientKey].select { |timestamp| timestamp >= windowStart }

    return false if @@countRequests[clientKey].length >= COUNT_RATE_LIMIT

    @@countRequests[clientKey] << now

    if @@countRequests.length > 10_000
      @@countRequests.delete_if { |_key, timestamps| timestamps.empty? }
    end

    true
  end
end
