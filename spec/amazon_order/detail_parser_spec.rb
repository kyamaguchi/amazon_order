require 'spec_helper'
require 'bigdecimal'
require 'json'

RSpec.describe AmazonOrder::DetailParser do
  Snapshot = AmazonOrder::Client::DetailSnapshot
  let(:fixture_path) { 'spec/fixtures/order_details/normal-sanitized.html' }
  let(:identity) { '111-0000002-0000002' }
  let(:snapshot) do
    Snapshot.new(
      order_identity: identity,
      path: fixture_path,
      html: File.read(fixture_path, encoding: Encoding::UTF_8)
    )
  end
  let(:purchased_fixture_path) { 'spec/fixtures/order_details/purchased-items-sanitized.html' }
  let(:purchased_snapshot) do
    Snapshot.new(
      order_identity: identity,
      path: purchased_fixture_path,
      html: File.read(purchased_fixture_path, encoding: Encoding::UTF_8)
    )
  end

  describe '.parse' do
    it 'fails closed when the confirmed fixture has no identifiable product rows' do
      result = described_class.parse([snapshot])

      expect(result).not_to be_success
      expect(result.orders).to eq([])
      expect(result.failed.first.to_hash).to include(
        'order_identity' => identity,
        'source_path' => fixture_path
      )
      expect(result.failed.first.reason).to eq(:unsupported_item_layout)
    end

    it 'reports malformed or unsupported documents instead of an empty success' do
      missing = Snapshot.new(order_identity: identity, path: 'missing.html', html: '<html></html>')
      mismatch = Snapshot.new(order_identity: 'other', path: 'wrong.html', html: snapshot.html)

      result = described_class.parse([missing, mismatch])

      expect(result.failed.map(&:reason)).to eq([:missing_order_identity, :wrong_order_identity])
    end

    it 'parses D01 rows without inventing a stable line identifier' do
      digital_html = purchased_snapshot.html
        .sub(identity, 'D01-0000000-0000000')
        .gsub(/&amp;lineItemId=LINE-0001/, '')
        .gsub('ご請求額：', 'この注文の合計:')
      digital = Snapshot.new(
        order_identity: 'D01-0000000-0000000',
        path: 'digital.html',
        html: digital_html
      )

      result = described_class.parse([digital])

      expect(result).to be_success
      order = result.orders.first
      expect(order.items.first.external_line_id).to be_nil
      expect(order.items.first.asin).to eq('B000000001')
      expect(order.items.first.diagnostics.map(&:code)).to include(:external_line_id_unavailable)
      expect(order.charged_total).to eq(BigDecimal('1334'))
    end

    it 'distinguishes failures in a batch and supports fail-fast without sessions' do
      client = AmazonOrder::Client.allocate
      expect(client).not_to receive(:session)
      expect(client).not_to receive(:sign_in_with_retry)

      result = client.parse_order_details([snapshot, snapshot], continue_on_error: false)

      expect(result.failed.size).to eq(1)
      expect(result.orders).to eq([])
    end

    it 'keeps a successful snapshot distinct from another snapshot failure' do
      result = described_class.parse([snapshot, purchased_snapshot])

      expect(result).not_to be_success
      expect(result.failed.map(&:reason)).to eq([:unsupported_item_layout])
      expect(result.orders.map(&:order_identity)).to eq([identity])
    end

    it 'parses the confirmed purchasedItems row locally using lineItemId' do
      result = described_class.parse([purchased_snapshot])

      expect(result).to be_success
      item = result.orders.first.items.first
      expect(item.external_line_id).to eq('LINE-0001')
      expect(item.asin).to eq('B000000001')
      expect(item.title).to eq('商品A')
      expect(item.display_amount).to eq(BigDecimal('1234'))
      expect(item.currency).to eq('JPY')
      expect(item.quantity).to be_nil
      expect(item.price_kind).to eq(:unit)
      expect(item.price_text).to eq('￥1,234￥1,234')
      expect(item.price_source).to eq(:order_detail)
      expect(item.line_status).to eq(:unknown)
      expect(item.refund_events).to eq([])
      expect(item.diagnostics.map(&:code)).to contain_exactly(:missing_quantity, :unknown_line_status)
      order = result.orders.first
      expect(order.item_subtotal).to eq(BigDecimal('1234'))
      expect(order.order_total).to eq(BigDecimal('1354'))
      expect(order.charged_total).to eq(BigDecimal('1334'))
      expect(order.items_total).to eq(BigDecimal('1234'))
      expect(order.adjustments.map { |line| [line.kind, line.display_amount] }).to eq([
        [:shipping_and_handling, BigDecimal('120')],
        [:discount, BigDecimal('-20')]
      ])
      expect(order.accounted_total).to eq(BigDecimal('1334'))
      expect(order.amount_lines.map(&:kind)).to eq([
        :item_subtotal, :shipping_and_handling, :discount
      ])
      expect(order.diagnostics).to be_empty
    end

    it 'does not read product links from personalization or another item row' do
      html = purchased_snapshot.html.sub(
        '</main>',
        '<div data-component="personalization"><a href="/dp/B999999999">広告商品</a></div></main>'
      )
      result = described_class.parse([
        Snapshot.new(order_identity: identity, path: 'local.html', html: html)
      ])

      expect(result.orders.first.items.map(&:asin)).to eq(['B000000001'])
    end

    it 'keeps local values associated when rows are reordered and ASINs repeat' do
      doc = Nokogiri::HTML(purchased_snapshot.html)
      row = doc.at_css(described_class::ITEM_SELECTOR)
      second = row.dup
      second.at_css('div[data-component="itemTitle"] a')['href'] = '/dp/B000000001'
      second.at_css('div[data-component="itemTitle"] a').content = '商品B'
      second.at_css('div[data-component="unitPrice"]').content = '￥2,345'
      connection = second.at_css('div[data-component="itemConnections"] a')
      connection['href'] = connection['href'].sub('LINE-0001', 'LINE-0002')
      row.add_previous_sibling(second)

      result = described_class.parse([
        Snapshot.new(order_identity: identity, path: 'reordered.html', html: doc.to_html)
      ])

      expect(result.orders.first.items.map { |item| [item.external_line_id, item.asin, item.title, item.display_amount] }).to eq([
        ['LINE-0002', 'B000000001', '商品B', BigDecimal('2345')],
        ['LINE-0001', 'B000000001', '商品A', BigDecimal('1234')]
      ])
    end

    it 'fails the order when lineItemId is missing or duplicated' do
      missing = purchased_snapshot.html.gsub(/&amp;lineItemId=LINE-0001/, '')
      duplicate_doc = Nokogiri::HTML(purchased_snapshot.html)
      duplicate_doc.at_css(described_class::ITEM_SELECTOR).add_next_sibling(
        duplicate_doc.at_css(described_class::ITEM_SELECTOR).dup
      )

      missing_result = described_class.parse([
        Snapshot.new(order_identity: identity, path: 'missing-id.html', html: missing)
      ])
      duplicate_result = described_class.parse([
        Snapshot.new(order_identity: identity, path: 'duplicate-id.html', html: duplicate_doc.to_html)
      ])

      expect(missing_result.failed.first.reason).to eq(:missing_external_line_id)
      expect(missing_result.failed.first.diagnostics.first.context).to eq(
        'row_count' => 1,
        'missing_line_id_count' => 1
      )
      expect(duplicate_result.failed.first.reason).to eq(:duplicate_external_line_id)
      expect(missing_result.orders).to be_empty
      expect(duplicate_result.orders).to be_empty
    end

    it 'distinguishes comma prices, zero, missing prices, and unparseable prices' do
      cases = {
        '￥1,234' => BigDecimal('1234'),
        '￥0' => BigDecimal('0'),
        '' => nil,
        '価格不明' => nil
      }

      cases.each do |text, expected|
        doc = Nokogiri::HTML(purchased_snapshot.html)
        doc.at_css('div[data-component="unitPrice"]').content = text
        result = described_class.parse([
          Snapshot.new(order_identity: identity, path: 'price.html', html: doc.to_html)
        ])
        item = result.orders.first.items.first

        expect(item.display_amount).to eq(expected)
        expect(item.price_text).to eq(text.empty? ? nil : text)
      end
    end

    it 'keeps unconfirmed summary labels unknown instead of treating them as adjustments' do
      doc = Nokogiri::HTML(purchased_snapshot.html)
      shipping = doc.css(described_class::SUMMARY_ROW_SELECTOR)[1]
      shipping.css('span')[0, 2].each { |span| span.content = 'その他：' }

      result = described_class.parse([
        Snapshot.new(order_identity: identity, path: 'unknown-summary.html', html: doc.to_html)
      ])
      order = result.orders.first

      expect(order.summary_lines.map(&:kind)).to include(:unknown)
      expect(order.adjustments.map(&:kind)).to eq([:discount])
      expect(order.accounted_total).to eq(BigDecimal('1214'))
      expect(order.diagnostics.map(&:code)).to include(:charged_total_mismatch)
    end

    it 'diagnoses a missing charged-total row without guessing another total' do
      doc = Nokogiri::HTML(purchased_snapshot.html)
      doc.css(described_class::SUMMARY_ROW_SELECTOR).last.remove

      result = described_class.parse([
        Snapshot.new(order_identity: identity, path: 'missing-total.html', html: doc.to_html)
      ])
      order = result.orders.first

      expect(order.charged_total).to be_nil
      expect(order.diagnostics.map(&:code)).to include(:missing_summary_line)
    end

    it 'reconciles from displayed subtotal without inferring quantity from unit price' do
      doc = Nokogiri::HTML(purchased_snapshot.html)
      doc.at_css('div[data-component="unitPrice"]').content = '￥617￥617'
      result = described_class.parse([
        Snapshot.new(order_identity: identity, path: 'multiple-units.html', html: doc.to_html)
      ])
      order = result.orders.first

      expect(order.items.first.display_amount).to eq(BigDecimal('617'))
      expect(order.items.first.quantity).to be_nil
      expect(order.items_total).to eq(BigDecimal('617'))
      expect(order.item_subtotal).to eq(BigDecimal('1234'))
      expect(order.accounted_total).to eq(BigDecimal('1334'))
      expect(order.diagnostics.map(&:code)).to contain_exactly(:item_subtotal_mismatch)
    end
  end

  describe 'models and serialization' do
    it 'preserves decimal precision, nil versus zero, enums, original text, refunds, and diagnostics' do
      diagnostic = described_class::Diagnostic.new(
        code: :unconfirmed_quantity,
        message: 'Quantity was not confirmed',
        context: { 'selector' => nil }
      )
      item = described_class::Item.new(
        external_line_id: 'line-confirmed-1',
        asin: 'b012345678',
        display_amount: BigDecimal('1234567890.123456789'),
        currency: 'JPY',
        quantity: nil,
        price_kind: :unknown,
        price_text: '￥1,234,567,890.123456789',
        line_status: :unknown,
        status_text: nil,
        refund_events: [],
        diagnostics: [diagnostic]
      )
      order = described_class::Order.new(
        order_identity: identity, source_path: fixture_path, items: [item]
      )
      hash = described_class::BatchResult.new(orders: [order], failed: []).to_hash
      parsed_json = JSON.parse(JSON.generate(hash))

      serialized_item = parsed_json['orders'][0]['items'][0]
      expect(serialized_item).to include(
        'asin' => 'B012345678',
        'display_amount' => '1234567890.123456789',
        'quantity' => nil,
        'price_kind' => 'unknown',
        'price_source' => 'order_detail',
        'line_status' => 'unknown',
        'price_text' => '￥1,234,567,890.123456789'
      )
      expect(serialized_item['refund_events']).to eq([])
      expect(serialized_item['diagnostics'][0]['code']).to eq('unconfirmed_quantity')
      expect(parsed_json['orders'][0]['order_identity']).to eq(identity)
      expect(parsed_json['orders'][0]).to include(
        'summary_lines' => [],
        'adjustments' => [],
        'item_subtotal' => nil,
        'order_total' => nil,
        'charged_total' => nil,
        'items_total' => '1234567890.123456789',
        'accounted_total' => '1234567890.123456789'
      )
    end

    it 'serializes confirmed summary and adjustment amounts without losing signs or zero' do
      result = described_class.parse([purchased_snapshot])
      hash = result.orders.first.to_hash

      expect(hash).to include(
        'item_subtotal' => '1234.0',
        'order_total' => '1354.0',
        'charged_total' => '1334.0',
        'currency' => 'JPY',
        'items_total' => '1234.0',
        'accounted_total' => '1334.0'
      )
      expect(hash['adjustments']).to include(
        include('kind' => 'shipping_and_handling', 'display_amount' => '120.0'),
        include('kind' => 'discount', 'display_amount' => '-20.0')
      )
    end

    it 'represents all unavailable item attributes without inventing values or refund events' do
      item = described_class::Item.new

      expect(item.to_hash).to include(
        'external_line_id' => nil, 'asin' => nil, 'title' => nil,
        'display_amount' => nil, 'currency' => nil, 'quantity' => nil,
        'price_kind' => 'unknown', 'line_status' => 'unknown',
        'refund_events' => []
      )
    end
  end
end
