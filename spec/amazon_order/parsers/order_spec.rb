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
    expect(order.order_details_path).to match(%r{\A/gp/})
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

  describe '#shipments' do
    it 'does not error' do
      expect { order.shipments }.not_to raise_error
    end
  end

  describe '#shipment_products' do
    it 'does not error' do
      expect { order.shipment_products.count }.not_to raise_error
    end
  end

  describe '#digital_products' do
    it 'does not error' do
      expect { order.digital_products.count }.not_to raise_error
    end
  end
end

def ensure_fixture_filepath(path)
  pending("Put your html in #{path} for testing") unless path && File.exists?(path)
  path
end


describe AmazonOrder::Parsers::Order do
  let(:parser) { AmazonOrder::Parser.new(filepath) }
  let(:order) { parser.orders[index_of_order] }

  context 'user fixtures' do
    TARGET_DIR = ENV['ORDERS_DIR'].presence || 'spec/fixtures/files'
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
    context 'order with digital deliveries' do
      let(:filepath) { 'spec/fixtures/files/order-amazon_com2017-contains-digital.html' }
      let(:index_of_order) { 0 }


      describe '#shipments' do
        it 'has no shipments' do
          expect(order.shipments.count).to eq 0
        end
      end
      describe '#shipment_products' do
        it 'has no shipment products' do
          expect(order.shipment_products.count).to eq 0
        end
      end
      describe '#digital_products' do
        it 'has a digital product' do
          expect(order.digital_products.count).to eq 1
        end
      end
    end

    context 'order with with home services' do
      let(:filepath) { 'spec/fixtures/files/order-2018-p1-20180129141532-contains-home-service.html' }
      let(:index_of_order) { 9 }
      include_examples 'generic order specs'
      describe '#shipments' do
        it 'has a shipments' do
          expect(order.shipments.count).to eq 1
        end
      end
      describe '#shipment_products' do
        it 'has a shipment product' do
          expect(order.shipment_products.count).to eq 1
        end
      end
      describe '#digital_products' do
        it 'has no digital products' do
          expect(order.digital_products.count).to eq 0
        end
      end
    end

    context 'order with with physical shipments' do
      let(:filepath) { 'spec/fixtures/files/order-2018-p1-20180129141532-contains-home-service.html' }
      let(:index_of_order) { 2 }
      include_examples 'generic order specs'
      describe '#shipments' do
        it 'has 3 shipments' do
          expect(order.shipments.count).to eq 3
        end
      end
      describe '#shipment_products' do
        it 'has 5 shipment products' do
          expect(order.shipment_products.count).to eq 5
        end
      end
      describe '#digital_products' do
        it 'has no digital products' do
          expect(order.digital_products.count).to eq 0
        end
      end
    end
  end
end
