require 'spec_helper'
require 'bigdecimal'
require 'stringio'

RSpec.describe AmazonOrder::DetailAudit do
  ListOrder = Struct.new(:order_number, :order_total)
  let(:identity) { '111-0000002-0000002' }
  let(:fixture_path) { 'spec/fixtures/order_details/purchased-items-sanitized.html' }
  let(:snapshot) do
    AmazonOrder::Client::DetailSnapshot.new(
      order_identity: identity,
      path: fixture_path,
      html: File.binread(fixture_path)
    )
  end
  let(:orders) { [ListOrder.new(identity, 1334.0)] }
  let(:load_result) do
    AmazonOrder::Client::DetailLoadBatchResult.new(loaded: [snapshot], failed: [])
  end
  let(:client) { AmazonOrder::Client.allocate }

  before do
    allow(client).to receive(:load_amazon_orders).and_return(orders)
    allow(client).to receive(:load_order_details).with(orders: orders).and_return(load_result)
    allow(client).to receive(:parse_order_details) do |loaded|
      AmazonOrder::DetailParser.parse(loaded)
    end
  end

  it 'runs the complete offline audit and reconciles list, item, and charged totals' do
    expect(client).not_to receive(:session)
    expect(client).not_to receive(:sign_in_with_retry)
    result = described_class.run(client)

    expect(result).to be_success
    expect(result).to be_coverage_success
    expect(result).to be_parse_success
    expect(result).to be_verification_success
    expect(result).to be_complete_success
    expect(result).to be_reconciliation_success
    expect(result.summary).to include(
      'list_orders' => 1,
      'loaded_snapshots' => 1,
      'missing_snapshots' => 0,
      'coverage_success' => true,
      'parsed_orders' => 1,
      'parsed_items' => 1,
      'parse_success' => true,
      'items_match_subtotal' => 1,
      'accounted_match_detail_total' => 1,
      'list_match_detail_total' => 1,
      'reconciliation_failures' => 0,
      'reconciliation_success' => true,
      'verification_success' => true,
      'complete_success' => true,
      'success' => true
    )
    expect(result.reconciliations.first.to_hash).to include(
      'list_total' => '1334.0',
      'items_total' => '1234.0',
      'item_subtotal' => '1234.0',
      'accounted_total' => '1334.0',
      'charged_total' => '1334.0',
      'detail_total_kind' => 'charged_total',
      'detail_total' => '1334.0',
      'list_matches_detail_total' => true
    )
  end

  it 'separates saved-snapshot coverage from monetary verification' do
    missing = AmazonOrder::Client::DetailResult.new(
      order_identity: '111-0000003-0000003',
      path: 'missing.html',
      status: :failed,
      reason: :missing_snapshot
    )
    partial_load = AmazonOrder::Client::DetailLoadBatchResult.new(
      loaded: [snapshot],
      failed: [missing]
    )
    allow(client).to receive(:load_order_details).with(orders: orders).and_return(partial_load)

    result = described_class.run(client)

    expect(result).not_to be_coverage_success
    expect(result).to be_parse_success
    expect(result).to be_verification_success
    expect(result).not_to be_complete_success
    expect(result.summary).to include(
      'missing_snapshots' => 1,
      'coverage_success' => false,
      'parse_success' => true,
      'verification_success' => true,
      'complete_success' => false
    )
  end

  it 'prints a compact JSON summary without dumping parsed private fields' do
    output = StringIO.new
    result = described_class.run(client)

    expect(result.pretty_print(output)).to equal(result)
    parsed = JSON.parse(output.string)
    expect(parsed).to include('list_orders' => 1, 'success' => true)
    expect(parsed).not_to have_key('reconciliations')
  end

  it 'accepts distinct list and accounted values when both are confirmed detail totals' do
    orders.first.order_total = 1234.0

    result = described_class.run(client)

    expect(result).to be_reconciliation_success
    reconciliation = result.reconciliations.first
    expect(reconciliation.list_matches_detail_total?).to be(true)
    expect(reconciliation.accounted_matches_detail_total?).to be(true)
    expect(reconciliation.detail_total_kind).to eq(:item_subtotal)
  end

  it 'bridges an unitemized merchandise discount and payment adjustment' do
    reconciliation = described_class::Reconciliation.new(
      list_total: BigDecimal('1000'),
      items_total: BigDecimal('100'),
      item_subtotal: BigDecimal('2000'),
      accounted_total: BigDecimal('2000'),
      charged_total: BigDecimal('806'),
      item_count: 1,
      order_kind: :digital
    )

    expect(reconciliation).to be_list_matches_detail_total
    expect(reconciliation.list_detail_relation).to eq(:between_subtotal_and_charged)
    expect(reconciliation.to_hash).to include(
      'detail_total_kind' => 'list_total_bridge',
      'detail_total' => '1000.0',
      'unitemized_merchandise_adjustment' => '-1000.0',
      'unitemized_payment_adjustment' => '-194.0'
    )
  end

  it 'marks mismatched saved-list totals without changing item prices' do
    orders.first.order_total = 1400.0
    result = described_class.run(client)

    expect(result).not_to be_success
    expect(result).not_to be_reconciliation_success
    expect(result.summary).to include(
      'list_match_detail_total' => 0,
      'reconciliation_failures' => 1,
      'reconciliation_mismatches' => [
        include(
          'item_count' => 1,
          'items_total' => '1234.0',
          'item_subtotal' => '1234.0',
          'accounted_total' => '1334.0',
          'charged_total' => '1334.0',
          'detail_total_kind' => 'charged_total',
          'detail_total' => '1334.0',
          'list_total' => '1400.0',
          'accounted_difference' => '0.0',
          'list_difference' => '66.0'
        )
      ]
    )
    expect(result.parse_result.orders.first.items_total).to eq(BigDecimal('1234'))
  end

  it 'caps the compact mismatch preview while preserving the total count' do
    result = described_class.run(client)
    mismatches = Array.new(25) do
      described_class::Reconciliation.new(
        order_identity: identity,
        list_total: BigDecimal('1400'),
        items_total: BigDecimal('1234'),
        item_subtotal: BigDecimal('1234'),
        accounted_total: BigDecimal('1334'),
        order_total: BigDecimal('1354'),
        charged_total: BigDecimal('1334'),
        item_count: 1,
        order_kind: :physical
      )
    end
    capped = described_class::Result.new(
      orders: result.orders,
      load_result: result.load_result,
      parse_result: result.parse_result,
      reconciliations: mismatches,
      directory: nil
    ).summary

    expect(capped['reconciliation_mismatches_total']).to eq(25)
    expect(capped['reconciliation_mismatches'].size).to eq(20)
    expect(capped['reconciliation_mismatches_truncated']).to eq(5)
  end

  it 'includes digital orders in the standard DetailAudit reconciliation' do
    digital_identity = 'D01-0000000-0000000'
    digital_doc = Nokogiri::HTML(snapshot.html)
    digital_doc.at_css('div[data-component="orderId"] span').content = digital_identity
    digital_doc.at_css('div[data-component="itemConnections"] a')['href'] = '/gp/buyagain'
    digital_doc.css(AmazonOrder::DetailParser::SUMMARY_ROW_SELECTOR).each do |row|
      row.remove unless row.text.include?('商品の小計') || row.text.include?('ご請求額')
    end
    digital_total = digital_doc.css(AmazonOrder::DetailParser::SUMMARY_ROW_SELECTOR).last
    digital_total.css('span').each do |span|
      span.content = span.text.include?('￥') ? '￥1,200' : 'この注文の合計:'
    end
    digital = AmazonOrder::Client::DetailSnapshot.new(
      order_identity: digital_identity,
      path: 'digital.html',
      html: digital_doc.to_html
    )
    orders << ListOrder.new(digital_identity, 1234.0)
    allow(client).to receive(:parse_order_details).and_return(
      AmazonOrder::DetailParser.parse([snapshot, digital])
    )

    result = described_class.run(client)

    expect(result).to be_success
    expect(result).to be_reconciliation_success
    expect(result.summary).to include(
      'parsed_orders' => 2,
      'parse_failures' => {},
      'item_diagnostics' => include('external_line_id_unavailable' => 1),
      'reconciliation_mismatches' => [],
      'reconciliation_success' => true,
      'success' => true
    )
  end

  it 'uses an optional directory without fetching and restores Capybara.save_path' do
    source_client = instance_double(AmazonOrder::Client)
    allow(client).to receive(:options).and_return(verbose: true)
    allow(source_client).to receive(:load_amazon_orders).and_return(orders)
    allow(source_client).to receive(:load_order_details).with(orders: orders).and_return(load_result)
    allow(source_client).to receive(:parse_order_details).with([snapshot]).and_return(
      AmazonOrder::DetailParser.parse([snapshot])
    )
    allow(AmazonOrder::Client).to receive(:new).with(
      hash_including(base_dir: 'orders')
    ).and_return(source_client)
    previous_save_path = Capybara.save_path

    result = described_class.run(client, directory: '/tmp/audit-source/orders')

    expect(result.directory).to eq('/tmp/audit-source/orders')
    expect(Capybara.save_path).to eq(previous_save_path)
  end
end
