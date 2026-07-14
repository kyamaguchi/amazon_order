require 'spec_helper'

RSpec.shared_examples "generic order specs" do
  describe '#order number' do
    it 'has a number ' do
      expect(order.order_number).to match(/\A[D\d][\d\-]+\z/)
    end
  end

  it 'has information' do
    expect(order.order_placed).to be_a(Date)
    expect(order.order_total).to be_a(Numeric)
    expect(order.order_total.to_s).to match(/\A[\d\.]+\z/)
    expect(order.order_details_path).not_to be_nil
    expect(order.fetched_at).to be_present
  end

  describe '#to_json' do
    it 'returns json' do
      json = order.to_json
      expect(json).to match(/"order_total"/)
      expect(json).to match(/"products"/)
      expect(json).to match(/"\d{4}-\d{2}-\d{2}"/) # date
      expect(parser.orders.to_json).to match(/\[{"order_placed":/)
    end
  end
end

describe 'AmazonOrder::Parsers' do

  describe AmazonOrder::Parsers::NormalOrder do
    describe '#order_details_path' do
      it 'finds an order details link outside the order header actions row' do
        node = Nokogiri::HTML.fragment(<<~HTML)
          <div class="order-card">
            <div class="order-header">
              <div class="a-col-right">
                <div class="a-row">注文番号 000-0000000-0000000</div>
                <div class="a-row"></div>
              </div>
            </div>
            <div class="product-image">
              <a class="a-link-normal" href="/products/example-item?ref=ppx_yo2ov_dt_b_fed_asin_title">Example item</a>
            </div>
            <ul class="yohtmlc-shipment-level-connections">
              <li>
                <a href="/hz/pwo?orderID=000-0000000-0000000" class="a-button-text">注文に関する問題</a>
              </li>
              <li>
                <a href="/your-orders/order-details?orderID=000-0000000-0000000&amp;ref=ppx_yo2ov_dt_b_fed_veo" class="a-button-text">
                  注文内容の表示と変更
                </a>
              </li>
            </ul>
          </div>
        HTML
        order = described_class.new(node)

        expect(order.order_details_path).to eq('/your-orders/order-details?orderID=000-0000000-0000000&ref=ppx_yo2ov_dt_b_fed_veo')
      end

      it 'finds a search-based order details link' do
        node = Nokogiri::HTML.fragment(<<~HTML)
          <div class="order-card">
            <div class="order-header">
              <div class="a-col-right">
                <div class="a-row">注文番号 000-0000000-0000000</div>
                <div class="a-row">
                  <a class="a-link-normal" href="/your-orders/search?search=digital-order-token&amp;ref=ppx_yo2ov_dt_b_fed_dss_shell_od_hz_search">
                    注文内容を表示
                  </a>
                  <a class="a-link-normal" href="/your-orders/invoice/popover?orderId=digital-order-token&amp;ref_=fed_invoice_ajax_dss">
                    請求書
                  </a>
                </div>
              </div>
            </div>
            <div class="product-image">
              <a class="a-link-normal" href="/products/example-item?ref=ppx_yo2ov_dt_b_fed_asin_title">Example item</a>
            </div>
          </div>
        HTML
        order = described_class.new(node)

        expect(order.order_details_path).to eq('/your-orders/search?search=digital-order-token&ref=ppx_yo2ov_dt_b_fed_dss_shell_od_hz_search')
      end

      it 'raises ParseError with the order node HTML when the details link is missing' do
        node = Nokogiri::HTML.fragment(<<~HTML)
          <div class="order-card">
            <div class="order-header">
              <div class="a-col-right">
                <div class="a-row">注文番号 000-0000000-0000000</div>
                <div class="a-row"><span>No details link</span></div>
              </div>
            </div>
          </div>
        HTML
        order = described_class.new(node, source_path: 'spec/fixtures/missing-details.html')

        expect {
          order.order_details_path
        }.to raise_error(AmazonOrder::Parsers::ParseError) { |error|
          expect(error.message).to include('AmazonOrder::Parsers::NormalOrder failed to parse order_details_path')
          expect(error.message).to include('selector="a[href*=order-details], a[href^=\"/your-orders/search\"]"')
          expect(error.message).to include('source_path="spec/fixtures/missing-details.html"')
          expect(error.message).to include('node_html=<div class="order-card">')
          expect(error.message).to include('<span>No details link</span>')
        }
      end
    end
  end
  let(:parser) { AmazonOrder::Parser.new(filepath) }
  let(:order) { parser.orders[index_of_order] }

  context 'user fixtures' do
    Dir.glob("#{TARGET_DIR}/*html").each do |filepath|
      context "with file (#{filepath})" do
        let(:filepath) { filepath }
        before do
          ensure_fixture_filepath(filepath)
        end
        AmazonOrder::Parser.new(filepath).orders.each_index do |i|
          context "order at index #{i}" do
            let(:index_of_order) { i }
            include_examples 'generic order specs'
          end
        end
      end
    end
  end

  context 'specific fixtures' do
    context 'order with mixed contents' do
      let(:filepath) { 'spec/fixtures/files/order-amazon_co_jp-2025-01-simplified.html' }

      describe '#orders' do
        it 'has orders' do
          expect(parser.orders.size).to eq 4
        end

        (0..3).to_a.each do |i|
          context "order at index #{i}" do
            let(:index_of_order) { i }
            include_examples 'generic order specs'
          end
        end

        describe '#products' do
          it 'has products' do
            expect(parser.orders.sum{|o| o.products.size }).to eq 7
          end
        end

        context 'with index 0' do
          let(:index_of_order) { 0 }

          it 'is a normal order' do
            expect(order.class).to eq AmazonOrder::Parsers::NormalOrder
          end

          describe '#products' do
            it 'has products' do
              expect(order.products.count).to eq 1
            end
          end

          describe '#order_total' do
            it 'has number' do
              expect(order.order_total).to eq 270
            end
          end
        end

        context 'with index 1' do
          let(:index_of_order) { 1 }

          it 'is a normal order' do
            expect(order.class).to eq AmazonOrder::Parsers::NormalOrder
          end

          describe '#products' do
            it 'has products' do
              expect(order.products.count).to eq 1
            end
          end

          describe '#order_total' do
            it 'has number' do
              expect(order.order_total).to eq 8200
            end
          end
        end

        context 'with index 2' do
          let(:index_of_order) { 2 }

          it 'is a normal order' do
            expect(order.class).to eq AmazonOrder::Parsers::DigitalOrder
          end

          describe '#products' do
            it 'has products' do
              expect(order.products.count).to eq 1
            end
          end

          describe '#order_total' do
            it 'has number' do
              expect(order.order_total).to eq 495
            end
          end
        end

        context 'with index 3' do
          let(:index_of_order) { 3 }

          it 'is a normal order' do
            expect(order.class).to eq AmazonOrder::Parsers::DigitalOrder
          end

          describe '#products' do
            it 'has products' do
              expect(order.products.count).to eq 4
            end
          end

          describe '#order_total' do
            it 'has number' do
              expect(order.order_total).to eq 8316
            end
          end
        end
      end
    end
  end
end
