require 'spec_helper'

describe AmazonOrder::Parsers::Shipment do
  Dir.glob("#{TARGET_DIR}/*html").each do |filepath|
    context "with file (#{filepath})" do
      parser = AmazonOrder::Parser.new(filepath)
      before { ensure_fixture_filepath(filepath) }

      parser.orders.each do |order|
        context "for order #{order.order_number} (#{order.order_type})" do

          order.shipments.each do |shipment|
            current_index = order.shipments.index(shipment)
            context "for shipment at #{current_index}" do
              describe '#shipment_note' do
                context 'with a service order' do
                  next unless order.order_type == :service_order
                  it 'returns nil' do
                    expect(shipment.shipment_note).to be_nil
                  end
                end
              end

              describe '#products' do
                it 'has products' do
                  expect(shipment.products.size).to be > 0
                end
              end
            end
          end
        end
      end
    end
  end
end
