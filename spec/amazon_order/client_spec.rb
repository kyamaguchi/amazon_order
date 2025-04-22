require 'spec_helper'

describe AmazonOrder::Client do
  before do
    skip('set your amazon credentials using envchain. See README and amazon_auth gem.') unless ENV['AMAZON_USERNAME_CODE']
    Capybara.save_path = "tmp/testdir/#{Time.now.strftime('%Y%m%d%H%M%S')}" # Switch working directory to start without the file for cookie
  end

  after do
    # Restore the default not to affect other spec
    Capybara.save_path = 'tmp'
    FileUtils.rm_rf('tmp/testdir') if File.exist?('tmp/testdir')
  end

  it "fetches amazon orders successfully" do
    client = AmazonOrder::Client.new(year_from: Time.current.year - 1, verbose: true, limit: 3)
    client.fetch_amazon_orders
    expect(client.session.current_url).to match(%r{/your-orders/orders})
    orders = client.load_amazon_orders
    expect(orders.size).to be > 0
  end

  it "logins successfully with keeping cookie" do
    client = AmazonOrder::Client.new(keep_cookie: true, verbose: true, limit: 2)
    client.sign_in
    client.go_to_amazon_order_page
    expect(client.session.current_url).to match(%r{/order-history})

    client.session.reset!
    client.sign_in
    client.go_to_amazon_order_page
    expect(client.session.current_url).to match(%r{/order-history})
  end
end
