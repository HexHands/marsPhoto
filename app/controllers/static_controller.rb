class StaticController < ApplicationController
  def explore
    render file: Rails.root.join('public','index.html'), layout: false
  end
end
