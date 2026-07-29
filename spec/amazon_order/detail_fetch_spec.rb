require 'spec_helper'

describe 'safe order detail fetching' do
  Order = Struct.new(:order_number, :order_details_path) unless defined?(Order)
  let(:identity) { '111-0000002-0000002' }
  let(:fixture_path) { 'spec/fixtures/order_details/normal-sanitized.html' }
  let(:fixture) { File.read(fixture_path, encoding: 'UTF-8') }
  let(:save_path) { "tmp/detail-fetch-#{Process.pid}-#{rand(100_000)}" }
  let(:auth_client) { double('amazon auth client') }
  let(:session) { double('session', current_url: 'https://www.amazon.co.jp/your-orders/orders') }
  let(:now) { Time.utc(2026, 7, 29, 12) }
  let(:logs) { [] }
  let(:client) { AmazonOrder::Client.new(base_dir: 'orders', clock: -> { now }) }
  let(:order) { Order.new(identity, "/gp/css/order-details?orderID=#{identity}&secret=do-not-log") }

  before do
    allow(AmazonAuth::Client).to receive(:new).and_return(auth_client)
    Capybara.save_path = save_path
    allow(client).to receive(:session).and_return(session)
    allow(client).to receive(:ensure_order_history_session)
    allow(client).to receive(:wait_for_selector)
    allow(client).to receive(:log) { |message| logs << message }
    allow(session).to receive(:visit)
    allow(session).to receive(:save_page) do |relative_path|
      path = File.join(Capybara.save_path, relative_path)
      FileUtils.mkdir_p(File.dirname(path))
      File.binwrite(path, fixture)
    end
  end

  after do
    Capybara.save_path = 'tmp'
    FileUtils.rm_rf(save_path)
  end

  def final_path
    client.send(:detail_path, identity)
  end

  it 'validates identity and confirmed normal-detail markers, then atomically installs the fixture' do
    result = client.fetch_order_details(orders: [order])

    expect(result.success?).to be true
    expect(result.downloaded.first.to_h).to include(
      order_identity: identity, path: final_path, status: :downloaded, reason: :downloaded
    )
    expect(File.binread(final_path)).to eq(fixture.b)
    expect(File.basename(final_path)).to eq("order-detail-#{Digest::SHA256.hexdigest(identity)}.html")
    expect(Dir.glob(File.join(File.dirname(final_path), '*.tmp'))).to be_empty
  end

  it 'uses the confirmed component nodes without requiring an optional page wrapper' do
    without_wrapper = fixture.sub('<main data-page-type="OrderDetails">', '').sub('</main>', '')
    allow(session).to receive(:save_page) do |relative_path|
      File.binwrite(File.join(Capybara.save_path, relative_path), without_wrapper)
    end

    result = client.fetch_order_details(orders: [order])

    expect(result.downloaded.size).to eq(1)
    expect(File.binread(final_path)).to eq(without_wrapper.b)
  end

  it 'rejects truncated and wrong-order pages without installing them' do
    [fixture.byteslice(0, fixture.bytesize / 2), fixture.sub(identity, '111-9999999-9999999')].each do |body|
      allow(session).to receive(:save_page) do |relative_path|
        File.binwrite(File.join(Capybara.save_path, relative_path), body)
      end
      result = client.fetch_order_details(orders: [order], force: true)
      expect(result.failed.first.reason).to satisfy { |reason| [:truncated_document, :wrong_order_identity].include?(reason) }
      expect(File).not_to exist(final_path)
    end
  end

  it 'skips a valid snapshot without network access and preserves bytes and mtime' do
    FileUtils.mkdir_p(File.dirname(final_path))
    File.binwrite(final_path, fixture)
    File.utime(now - 60, now - 60, final_path)
    old_mtime = File.mtime(final_path)

    result = client.fetch_order_details(orders: [order])

    expect(result.skipped.first.reason).to eq(:fresh_snapshot)
    expect(session).not_to have_received(:visit)
    expect(File.binread(final_path)).to eq(fixture.b)
    expect(File.mtime(final_path)).to eq(old_mtime)
  end

  it 'uses inclusive TTL boundaries and refreshes an expired snapshot' do
    FileUtils.mkdir_p(File.dirname(final_path))
    File.binwrite(final_path, fixture)
    File.utime(now - 3600, now - 3600, final_path)

    expect(client.fetch_order_details(orders: [order], freshness: 3600).skipped.size).to eq(1)
    File.utime(now - 3601, now - 3601, final_path)
    expect(client.fetch_order_details(orders: [order], ttl: 3600).downloaded.size).to eq(1)
  end

  it 'force-refreshes but preserves the old snapshot on transport or validation failure' do
    FileUtils.mkdir_p(File.dirname(final_path))
    old = fixture.sub('明日到着予定', '保存済み')
    File.binwrite(final_path, old)

    allow(session).to receive(:visit).and_raise('transport')
    expect(client.fetch_order_details(orders: [order], force: true).failed.first.reason).to eq(:fetch_failed)
    expect(File.binread(final_path)).to eq(old.b)

    allow(session).to receive(:visit)
    allow(session).to receive(:save_page) { |relative| File.binwrite(File.join(Capybara.save_path, relative), '') }
    expect(client.fetch_order_details(orders: [order], force: true).failed.first.reason).to eq(:empty_document)
    expect(File.binread(final_path)).to eq(old.b)
    expect(Dir.glob(File.join(File.dirname(final_path), '*.tmp'))).to be_empty
  end

  it 'preserves the old snapshot when atomic replacement fails' do
    FileUtils.mkdir_p(File.dirname(final_path))
    old = fixture.sub('明日到着予定', '保存済み')
    File.binwrite(final_path, old)
    allow(File).to receive(:rename).and_raise(Errno::EIO, 'rename failed')

    result = client.fetch_order_details(orders: [order], force: true)

    expect(result.failed.first.reason).to eq(:save_failed)
    expect(File.binread(final_path)).to eq(old.b)
    expect(Dir.glob(File.join(File.dirname(final_path), '*.tmp'))).to be_empty
  end

  it 'returns diagnostics for missing links and continues with valid orders' do
    result = client.fetch_order_details(orders: [Order.new('missing', nil), order])
    expect(result.failed.first.reason).to eq(:missing_link)
    expect(result.downloaded.size).to eq(1)
  end

  it 'applies fail-fast behavior to candidate validation failures' do
    invalid_cases = [
      [Order.new(nil, '/detail/missing-identity'), :missing_identity],
      [Order.new('missing-link', nil), :missing_link],
      [Order.new('invalid-url', 'http://['), :invalid_url]
    ]

    invalid_cases.each do |invalid_order, reason|
      expect do
        client.fetch_order_details(orders: [invalid_order, order], continue_on_error: false)
      end.to raise_error(AmazonOrder::Client::DetailFetchError, reason.to_s)
    end
    expect(session).not_to have_received(:visit)
  end

  it 'fails fast on conflicting links before visiting candidates' do
    conflicting = [
      Order.new(identity, "/gp/css/order-details?orderID=#{identity}"),
      Order.new(identity, "/gp/css/order-details?orderID=#{identity}-different"),
      order
    ]

    expect do
      client.fetch_order_details(orders: conflicting, continue_on_error: false)
    end.to raise_error(AmazonOrder::Client::DetailFetchError, 'conflicting_links')
    expect(session).not_to have_received(:visit)
  end

  it 'does not reintroduce a conflicted identity from later duplicates' do
    conflicting = [
      Order.new(identity, "/gp/css/order-details?orderID=#{identity}"),
      Order.new(identity, "/gp/css/order-details?orderID=#{identity}-different"),
      Order.new(identity, "/gp/css/order-details?orderID=#{identity}")
    ]

    result = client.fetch_order_details(orders: conflicting)

    expect(result.failed.map(&:reason)).to eq([:conflicting_links])
    expect(session).not_to have_received(:visit)
  end

  it 'never logs raw identities or complete URLs' do
    client.fetch_order_details(orders: [order])
    messages = logs.join('\n')
    expect(messages).not_to include(identity, 'secret=do-not-log', order.order_details_path)
    expect(messages).to include(Digest::SHA256.hexdigest(identity)[0, 12])
  end

  it 'keeps detail snapshots outside the existing order-list glob and loader' do
    FileUtils.mkdir_p(File.dirname(final_path))
    File.binwrite(final_path, fixture)
    expect(Dir.glob(client.file_glob_pattern)).not_to include(final_path)
    allow(client).to receive(:parse_amazon_orders).and_return([])
    client.load_amazon_orders
    expect(client).to have_received(:parse_amazon_orders).with([])
  end

  it 'loads valid saved details with their identities without authentication or network access' do
    FileUtils.mkdir_p(File.dirname(final_path))
    File.binwrite(final_path, fixture)
    allow(client).to receive(:ensure_order_history_session)

    result = client.load_order_details(orders: [order, order])

    expect(result.success?).to be true
    expect(result.loaded.size).to eq(1)
    expect(result.first.to_h).to include(order_identity: identity, path: final_path, html: fixture.b)
    expect(client).not_to have_received(:ensure_order_history_session)
    expect(session).not_to have_received(:visit)
    expect(logs).to include(include('Loaded order detail', 'order_ref=', 'reason=loaded'))
    expect(logs.join('\n')).not_to include(identity)
  end

  it 'reports missing and invalid saved details without fetching' do
    FileUtils.mkdir_p(File.dirname(final_path))
    File.binwrite(final_path, '<html><body>incomplete</body></html>')
    missing = Order.new('missing-snapshot', '/detail/missing')

    result = client.load_order_details(orders: [order, missing])

    expect(result).to be_empty
    expect(result.failed.group_by(&:reason).transform_values(&:size)).to eq(
      missing_order_identity: 1,
      missing_snapshot: 1
    )
    expect(session).not_to have_received(:visit)
    expect(logs).to include(include('Failed to load order detail', 'reason=missing_order_identity'))
    expect(logs).to include(include('Failed to load order detail', 'reason=missing_snapshot'))
    expect(logs.join('\n')).not_to include(identity, 'missing-snapshot')
  end

  it 'maps distinct identities to deterministic collision-resistant paths inside the root' do
    same = client.send(:detail_path, identity)
    other = client.send(:detail_path, '../../another-order')
    expect(client.send(:detail_path, identity)).to eq(same)
    expect(other).not_to eq(same)
    expect(File.expand_path(other)).to start_with(File.expand_path(File.join(save_path, 'orders', 'details')) + '/')
  end
end
