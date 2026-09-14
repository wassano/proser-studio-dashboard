require "test_helper"

class ConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false
  def setup
    skip "Concorrência é validada com DATABASE_URL apontando para PostgreSQL" unless ActiveRecord::Base.connection.adapter_name == "PostgreSQL"
    [DownloadGrant, ReleaseAsset, Release, Installation, License, RegistrationSetting, Plan, RequestNonce, AuditEvent, AdminSession].each(&:delete_all)
    super
    RegistrationSetting.current.update!(installation_limit: 3)
  end
  def teardown
    if @keydir
      [DownloadGrant, ReleaseAsset, Release, Installation, License, RegistrationSetting, Plan, RequestNonce, AuditEvent, AdminSession].each(&:delete_all)
    end
    super
  end
  test "concurrent admissions cannot exceed the global installation limit" do
    errors = Queue.new
    threads = 8.times.map do |index|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          key = device_key
          auth = Struct.new(:device_id, :key_pem).new(Digest::SHA256.hexdigest(key.public_to_der), key.public_to_pem)
          Registration.call(auth, metadata.merge(computer_name: "PC-#{index}"), "127.0.0.1")
        end
      rescue StandardError => error
        errors << error
      end
    end
    threads.each(&:join)
    assert_equal 0, errors.size, errors.size.positive? ? errors.pop.full_message : nil
    assert_equal 8, Installation.count
    assert_equal 3, Installation.where(status: "active").count
    assert_equal 5, Installation.where(status: "pending").count
    assert_equal 3, License.count
  end
end
