# frozen_string_literal: true

# Updated Api::V1::PhotosController
#
# This controller supports optional rover_id and sol ranges, optimizes queries to
# issue a single SQL request, and enforces a rate limit of 20 requests per minute per IP.
# All local variables use camelCase as requested.

class Api::V1::PhotosController < ApplicationController
  # Rate limit requests to 20 per minute per IP
  before_action :rate_limit

  # GET /api/v1/photos or /api/v1/rovers/:rover_id/photos
  # Supports optional rover_id, sol, start_sol/end_sol, earth_date, camera, page, per_page params.
  def index
    roverName = params[:rover_id]
    rover     = roverName.present? ? Rover.find_by(name: roverName.to_s.titleize) : nil

    # Return a 400 if rover_id was supplied but no matching rover was found
    if roverName.present? && rover.nil?
      render json: { errors: 'Invalid Rover Name' }, status: :bad_request and return
    end

    render json: photos(rover), each_serializer: PhotoSerializer, root: :photos
  end

  # GET /api/v1/photos/:id
  def show
    photo = Photo.find(params[:id])
    render json: photo, serializer: PhotoSerializer, root: :photo
  end

  private

  # Rate limiting logic
  # Uses Rails.cache to count requests from each IP. If the count exceeds
  # 20 within a 60-second window, a 429 Too Many Requests response is returned.
  def rate_limit
    ipAddress    = request.ip
    rateKey      = "photos_rate_limit:#{ipAddress}"
    requestCount = Rails.cache.read(rateKey).to_i
    if requestCount >= 20
      render json: { errors: 'Rate limit exceeded: max 20 requests per minute' }, status: :too_many_requests and return
    else
      Rails.cache.write(rateKey, requestCount + 1, expires_in: 1.minute)
    end
  end

  # Strong parameters for photo search. Accepts sol, start_sol/end_sol, camera,
  # earth_date, page/per_page and rover_id.
  def photo_params
    params.permit(:sol, :start_sol, :end_sol, :camera, :earth_date, :page, :per_page, :rover_id)
  end

  # Build an ActiveRecord::Relation filtered by the provided parameters.
  # If a rover is provided, the scope is limited to that rover's photos. Otherwise, all photos are queried.
  def photos(rover)
    # Choose base scope: rover.photos if rover given, else Photo.all
    photoScope = rover ? rover.photos : Photo.all

    # Apply sol range, sol, or earth_date filters
    if photo_params[:start_sol].present? && photo_params[:end_sol].present?
      startSol = photo_params[:start_sol].to_i
      endSol   = photo_params[:end_sol].to_i
      photoScope = photoScope.where(sol: startSol..endSol)
    elsif photo_params[:sol].present?
      photoScope = photoScope.where(sol: photo_params[:sol].to_i)
    elsif photo_params[:earth_date].present?
      photoScope = photoScope.where(earth_date: Date.strptime(photo_params[:earth_date]))
    end

    # Apply camera filter with a join to avoid an extra lookup query
    if photo_params[:camera].present?
      cameraName = photo_params[:camera].to_s.upcase
      photoScope = photoScope.joins(:camera).where(cameras: { name: cameraName })
    end

    # Consistent ordering by camera_id then id
    photoScope = photoScope.order(:camera_id, :id)

    # Pagination
    if photo_params[:page].present?
      perPage = (photo_params[:per_page].presence || 25).to_i
      photoScope = photoScope.page(photo_params[:page]).per(perPage)
    end

    photoScope
  end
end
