require 'spec_helper'

describe AmazonOrder::Parsers::Product do
  Dir.glob("#{TARGET_DIR}/*html").each do |filepath|
    context "with file (#{filepath})" do
      parser = AmazonOrder::Parser.new(filepath)
      before { ensure_fixture_filepath(filepath) }

      parser.orders.each do |order|
        context "for order #{order.order_number}" do

          order.shipments.each do |shipment|
            current_index = order.shipments.index(shipment)
            context "for shipment at #{current_index}" do

              shipment.products.each do |product|
                current_index = shipment.products.index(product)
                context "for product at #{current_index}" do

                  it 'has information' do
                    expect(product.title).to be_present
                    expect(product.path).to match(%r{\A/gp/product/})
                    expect(product.content).to be_present
                    expect(product.image_url).to match(%r{/images/})
                    expect(product.fetched_at).to be_present
                  end

                end
              end
            end
          end
        end
      end
    end
  end
end

