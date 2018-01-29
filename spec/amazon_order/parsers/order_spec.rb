require 'spec_helper'

describe AmazonOrder::Parsers::Order do
  TARGET_DIR = ENV['ORDERS_DIR'].presence || 'spec/fixtures/files'

  def ensure_fixture_filepath(path)
    pending("Put your html in #{path} for testing") unless path && File.exists?(path)
    path
  end

  Dir.glob("#{TARGET_DIR}/*html").each do |filepath|
    context "with file (#{filepath})" do
      parser = AmazonOrder::Parser.new(filepath)
      before do
        ensure_fixture_filepath(filepath)
      end

      parser.orders.each do |order|
        current_index = parser.orders.index(order)
        # next unless current_index == 3
        context "for order #{current_index}" do

          it "has information" do
            expect(order.order_placed).to be_a(Date)
            expect(order.order_number).to match(/\A[D\d][\d\-]+\z/)
            expect(order.order_total).to be_a(Numeric)
            expect(order.order_total.to_s).to match(/\A[\d\.]+\z/)
            expect(order.order_details_path).to match(%r{\A/gp/})
            expect(order.fetched_at).to be_present
            expect(order.products.size).to be > 0
          end

          it "prints json" do
            json = order.to_json
            expect(json).to match(/"order_total"/)
            expect(json).to match(/"products"/)
            expect(json).to match(/"\d{4}-\d{2}-\d{2}"/) # date
            expect(parser.orders.to_json).to match(/\[{"order_placed":/)
          end
        end
      end
    end
  end
end
