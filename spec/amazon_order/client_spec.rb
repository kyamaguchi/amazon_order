require 'spec_helper'

describe AmazonOrder::Client do
  Order = Struct.new(:order_number, :order_details_path)

  describe '#fetch_amazon_orders with order details enabled' do
    let(:auth_client) { double('amazon auth client') }
    let(:client) do
      AmazonOrder::Client.new(
        fetch_order_details: true,
        year_from: 2025,
        year_to: 2025,
        limit: 2
      )
    end

    before do
      allow(AmazonAuth::Client).to receive(:new).and_return(auth_client)
      allow(client).to receive(:sign_in_and_open_order_history)
    end

    it 'fetches details only for order-list pages downloaded by the current run' do
      current_paths = %w[tmp/orders/order-2025-p1.html tmp/orders/order-2025-p2.html]
      current_orders = [Order.new('current-1', '/detail/1')]
      allow(client).to receive(:fetch_orders_for_year).with(year: 2025).and_return(current_paths)
      allow(client).to receive(:parse_amazon_orders).with(current_paths).and_return(current_orders)
      allow(client).to receive(:fetch_order_details)
      expect(client).not_to receive(:load_amazon_orders)

      client.fetch_amazon_orders

      expect(client).to have_received(:fetch_order_details).with(orders: current_orders)
    end
  end

  describe 'sign-in retry from #fetch_amazon_orders' do
    let(:auth_client) { double('amazon auth client') }
    let(:session) { double('session', current_url: 'https://www.amazon.co.jp/') }
    let(:client) do
      AmazonOrder::Client.new(year_from: 2025, year_to: 2025, sign_in_attempts: 3)
    end

    before do
      allow(AmazonAuth::Client).to receive(:new).and_return(auth_client)
      allow(client).to receive(:session).and_return(session)
      allow(client).to receive(:sign_in)
      allow(client).to receive(:go_to_amazon_order_page).and_return(false, false, true)
      allow(client).to receive(:fetch_orders_for_year).and_return([])
      allow(client).to receive(:log)
      allow(session).to receive(:visit)
    end

    it 'revisits the Amazon origin and retries up to the configured attempt count' do
      client.fetch_amazon_orders

      expect(client).to have_received(:sign_in).exactly(3).times
      expect(session).to have_received(:visit).with('https://www.amazon.co.jp/').twice
      expect(client).to have_received(:log).with(include('attempt 1/3 failed'))
      expect(client).to have_received(:log).with(include('attempt 2/3 failed'))
    end
  end

  describe '#fetch_order_details' do
    let(:save_path) { "tmp/client-unit-#{Process.pid}" }
    let(:auth_client) { double('amazon auth client') }
    let(:session) { double('session', current_url: 'https://www.amazon.co.jp/your-orders/orders') }
    let(:client) { AmazonOrder::Client.new(base_dir: 'orders') }

    before do
      allow(AmazonAuth::Client).to receive(:new).and_return(auth_client)
      Capybara.save_path = save_path
      allow(client).to receive(:session).and_return(session)
      allow(client).to receive(:wait_for_selector).with('body')
      allow(client).to receive(:doc).and_return(Nokogiri::HTML('<html><body>detail</body></html>'))
      allow(client).to receive(:log)
      allow(session).to receive(:visit)
      allow(session).to receive(:save_page)
    end

    after do
      Capybara.save_path = 'tmp'
      FileUtils.rm_rf(save_path)
    end

    def orders(*values)
      allow(client).to receive(:load_amazon_orders).and_return(values)
    end

    it 'deduplicates by order number, resolves relative links against the original origin, and saves safely' do
      orders(
        Order.new('123/45:*?', '/gp/order-details?ref_=one'),
        Order.new('123/45:*?', 'https://www.amazon.co.jp/gp/order-details?ref_=two')
      )

      client.fetch_order_details

      expect(session).to have_received(:visit).once.with('https://www.amazon.co.jp/gp/order-details?ref_=one')
      expect(session).to have_received(:save_page).once.with(
        match(%r{\Aorders/details/order-detail-123_45-\d+\.html\z})
      )
    end

    it 'visits Amazon and Audible absolute URLs without changing them' do
      orders(
        Order.new('amazon-1', 'https://www.amazon.com/gp/order-details?id=1'),
        Order.new('audible-1', 'https://www.audible.co.jp/account/purchase-history?id=2')
      )

      client.fetch_order_details

      expect(session).to have_received(:visit).with('https://www.amazon.com/gp/order-details?id=1')
      expect(session).to have_received(:visit).with('https://www.audible.co.jp/account/purchase-history?id=2')
      expect(client).to have_received(:log).with(
        include('Fetching order detail (1/2)', 'order=amazon-1')
      )
      expect(client).to have_received(:log).with(
        include('Saving order detail (2/2)', 'order=audible-1')
      )
    end

    it 'skips an existing detail unless force is enabled' do
      orders(Order.new('existing-1', '/detail/1'))
      directory = File.join(save_path, 'orders', 'details')
      FileUtils.mkdir_p(directory)
      File.write(File.join(directory, 'order-detail-existing-1-20200101000000000.html'), 'saved')

      client.fetch_order_details
      expect(session).not_to have_received(:visit)

      client.fetch_order_details(force: true)
      expect(session).to have_received(:visit).once
    end

    it 'does not save a sign-in redirect' do
      orders(Order.new('auth-1', '/detail/1'))
      allow(session).to receive(:current_url).and_return(
        'https://www.amazon.co.jp/your-orders/orders',
        'https://www.amazon.co.jp/ap/signin'
      )

      client.fetch_order_details

      expect(session).not_to have_received(:save_page)
      expect(client).to have_received(:log).with(include('order=auth-1', 'url=https://www.amazon.co.jp/detail/1'))
    end

    it 'logs one failed order and continues with the next one' do
      orders(Order.new('failed-1', '/detail/1'), Order.new('ok-2', '/detail/2'))
      allow(session).to receive(:visit) do |url|
        raise 'network failure' if url.end_with?('/detail/1')
      end

      client.fetch_order_details(continue_on_error: true)

      expect(session).to have_received(:visit).with('https://www.amazon.co.jp/detail/2')
      expect(session).to have_received(:save_page).once.with(include('order-detail-ok-2-'))
      expect(client).to have_received(:log).with(include('order=failed-1', 'url=https://www.amazon.co.jp/detail/1'))
    end
  end

  describe '#sign_in' do
    let(:auth_client) { double('amazon auth client', sign_in: nil) }
    let(:session) { double('session', current_url: 'https://www.amazon.co.jp/ap/signin') }
    let(:client) { AmazonOrder::Client.new }

    before do
      allow(AmazonAuth::Client).to receive(:new).and_return(auth_client)
      allow(client).to receive(:session).and_return(session)
      allow(client).to receive(:doc).and_return(Nokogiri::HTML('<input id="ap_email">'))
    end

    it 'stops immediately when amazon_auth leaves the browser on a sign-in page' do
      expect { client.sign_in }.to raise_error(
        AmazonOrder::Client::AuthenticationError,
        include('https://www.amazon.co.jp/ap/signin')
      )
    end
  end

  describe 'live Amazon access' do
    before do
      skip('set your amazon credentials using envchain. See README and amazon_auth gem.') unless ENV['AMAZON_USERNAME_CODE']
    end

    before do
      # Switch working directory to start without the file for cookie
      Capybara.save_path = "tmp/testdir/#{Time.now.strftime('%Y%m%d%H%M%S')}"
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
end
