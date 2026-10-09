require "test_helper"

class AdminReleaseGroupsTest < ActionDispatch::IntegrationTest
  test "pagination counts versions and keeps every platform and channel together" do
    101.times do |number|
      %w[win-x64 mac-arm64].each { |target| Release.create!(version: "1.0.#{number}", target: target) }
    end
    Release.create!(version: "1.0.100", target: "win-x64", channel: "beta")
    # A late upload for an older version must not change semantic version order.
    Release.create!(version: "1.0.0", target: "mac-x64")
    login
    get "/api/admin/releases", params: { page: 1 }
    assert_response :success
    body = response.parsed_body
    assert_equal 101, body.fetch("total")
    groups = body.fetch("items").group_by { |item| item.fetch("version") }
    assert_equal (1..100).to_a.reverse.map { |number| "1.0.#{number}" }, groups.keys
    assert_equal 3, groups.fetch("1.0.100").size
    assert_equal %w[beta stable], groups.fetch("1.0.100").map { |item| item.fetch("channel") }.uniq.sort
    assert groups.except("1.0.100").values.all? { |items| items.size == 2 }
    get "/api/admin/releases", params: { page: 2 }
    assert_response :success
    assert_equal ["1.0.0"], response.parsed_body.fetch("items").map { |item| item.fetch("version") }.uniq
    assert_equal %w[mac-arm64 mac-x64 win-x64], response.parsed_body.fetch("items").map { |item| item.fetch("target") }.sort
    get "/api/admin/releases", params: { page: 3 }
    assert_response :success
    assert_empty response.parsed_body.fetch("items")
  end
end
