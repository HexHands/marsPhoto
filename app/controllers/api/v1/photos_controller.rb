# app/controllers/api/v1/photos_controller.rb
class Api::V1::PhotosController < ApplicationController

  def index
    # allow rover_id to be optional
    roverName   = params[:rover_id]
    rover       = roverName.present? ? Rover.find_by(name: roverName.to_s.titleize) : nil

    # if rover_id was supplied but not found, return an error
    if roverName.present? && rover.nil?
      render(json: { errors: "Invalid Rover Name" }, status: :bad_request) and return
    end

    render json: photos(rover), each_serializer: PhotoSerializer, root: :photos
  end

  private

  def photoParams
    params.permit(:sol, :start_sol, :end_sol, :camera, :earth_date, :page, :per_page, :rover_id)
  end

  def photos(rover)
    baseScope = rover ? rover.photos : Photo.all

    scoped = baseScope.order(:camera_id, :id).search(photoParams, rover)

    if params[:page].present?
      perPage = (params[:per_page].presence || 25).to_i
      scoped  = scoped.page(params[:page]).per(perPage)
    end
    scoped
  end
end
