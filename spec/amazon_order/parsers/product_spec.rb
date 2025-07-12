require 'spec_helper'

describe AmazonOrder::Parsers::Product do
  Dir.glob("#{TARGET_DIR}/*html").each do |filepath|
    context "with file (#{filepath})" do
      parser = AmazonOrder::Parser.new(filepath)
      before { ensure_fixture_filepath(filepath) }

      parser.orders.each do |order|
        context "for order #{order.order_number}" do
          order.products.each do |product|
            it 'has information' do
              expect(product.title).not_to be_nil
              expect { product.path }.not_to raise_error
              expect(product.content).not_to be_nil
              expect(product.fetched_at).to be_present
            end
          end
        end
      end
    end
  end
end

