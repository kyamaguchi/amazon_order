require "spec_helper"

RSpec.describe AmazonOrder do
  it "has a version number" do
    expect(AmazonOrder::VERSION).not_to be nil
  end
end
