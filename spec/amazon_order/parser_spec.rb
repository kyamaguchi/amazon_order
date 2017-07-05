require 'spec_helper'

describe AmazonOrder::Parser do
  TARGET_DIR = ENV['ORDERS_DIR'].presence || 'spec/fixtures/files'

  def ensure_fixture_filepath(path)
    pending("Put your html in #{path} for testing") unless path && File.exists?(path)
    path
  end

  context 'with single file' do
    before do
      filepath = ensure_fixture_filepath(Dir.glob("#{TARGET_DIR}/*html").last)
      @parser = AmazonOrder::Parser.new(ensure_fixture_filepath(filepath))
    end

    it "finds selector of order" do
      expect(@parser.body).to be_present
      expect(@parser.doc.css(".order").size).to be > 0
    end

    it "finds orders" do
      expect(@parser.orders.size).to be > 0
      expect(@parser.orders.first).to be_a(AmazonOrder::Parsers::Order)
    end
  end

  describe 'orders' do
    Dir.glob("#{TARGET_DIR}/*html").each do |filepath|
      context "with file (#{filepath})" do
        before do
          @parser = AmazonOrder::Parser.new(ensure_fixture_filepath(filepath))
        end

        it "has information" do
          order = @parser.orders.last
          expect(@parser.fetched_at).to be_present

          expect(order.order_placed).to be_a(Date)
          expect(order.order_number).to match(/\A[D\d][\d\-]+\z/)
          expect(order.order_total).to be_a(Numeric)
          expect(order.order_total.to_s).to match(/\A[\d\.]+\z/)
          expect(order.order_details_path).to match(%r{\A/gp/})
          expect(order.fetched_at).to be_present

          expect(order.products.size).to be > 0
          product = order.products.first
          expect(product.title).to be_present
          expect(product.path).to match(%r{\A/gp/product/})
          expect(product.content).to be_present
          expect(product.image_url).to match(%r{/images/I/[^.]+\.jpg})
          expect(product.fetched_at).to be_present
        end

        it "prints json" do
          order = @parser.orders.last
          json = order.to_json
          expect(json).to match(/"order_total"/)
          expect(json).to match(/"products"/)
          expect(json).to match(/"\d{4}-\d{2}-\d{2}"/) # date
          expect(@parser.orders.to_json).to match(/\[{"order_placed":/)
        end
      end
    end
  end

  describe '#get_original_image_url' do
    it "removes image options from url" do
      parser = AmazonOrder::Parsers::Product.new(nil)
      {
        'https://images-fe.ssl-images-amazon.com/images/I/51lqodTD6KL.jpg' => 'https://images-fe.ssl-images-amazon.com/images/I/51lqodTD6KL.jpg',
        'https://images-fe.ssl-images-amazon.com/images/I/51lqodTD6KL._UY250_.jpg' => 'https://images-fe.ssl-images-amazon.com/images/I/51lqodTD6KL.jpg',
        'https://images-na.ssl-images-amazon.com/images/I/51i0hr6kccL._AC_US218_.jpg' => 'https://images-na.ssl-images-amazon.com/images/I/51i0hr6kccL.jpg',
        'https://images-na.ssl-images-amazon.com/images/I/512S13U-XPL._SL500_SR103,135_.jpg' => 'https://images-na.ssl-images-amazon.com/images/I/512S13U-XPL.jpg',
      }.each do |url,expected|
        expect(parser.get_original_image_url(url)).to eql(expected)
      end
    end
  end
end
