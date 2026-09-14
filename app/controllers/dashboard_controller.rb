class DashboardController < ApplicationController
  def index
    path = Rails.root.join("public/index.html")
    return render plain: "Compile o frontend: npm --prefix frontend run build", status: :service_unavailable unless path.file?
    render html: path.read.html_safe, layout: false
  end
end
