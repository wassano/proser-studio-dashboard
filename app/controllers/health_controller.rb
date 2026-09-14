class HealthController < ActionController::Base
  def show
    ActiveRecord::Base.connection.execute("SELECT 1")
    head :ok
  end
end
