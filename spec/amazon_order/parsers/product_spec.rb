require 'spec_helper'

describe AmazonOrder::Parsers::Product do
  TARGET_DIR = ENV['ORDERS_DIR'].presence || 'spec/fixtures/files'

  def ensure_fixture_filepath(path)
    pending("Put your html in #{path} for testing") unless path && File.exists?(path)
    path
  end

  describe '#get_original_image_url' do
    it "removes image options from url" do
      parser = AmazonOrder::Parsers::Product.new(nil)
      {
        'https://images-fe.ssl-images-amazon.com/images/I/51lqodTD6KL.jpg' => 'https://images-fe.ssl-images-amazon.com/images/I/51lqodTD6KL.jpg',
        'https://images-fe.ssl-images-amazon.com/images/I/51lqodTD6KL._UY250_.jpg' => 'https://images-fe.ssl-images-amazon.com/images/I/51lqodTD6KL.jpg',
        'https://images-na.ssl-images-amazon.com/images/I/51i0hr6kccL._AC_US218_.jpg' => 'https://images-na.ssl-images-amazon.com/images/I/51i0hr6kccL.jpg',
        'https://images-na.ssl-images-amazon.com/images/I/512S13U-XPL._SL500_SR103,135_.jpg' => 'https://images-na.ssl-images-amazon.com/images/I/512S13U-XPL.jpg',
      }.each do |url, expected|
        expect(parser.get_original_image_url(url)).to eql(expected)
      end
    end
  end
  
  Dir.glob("#{TARGET_DIR}/*html").each do |filepath|
    context "with file (#{filepath})" do
      parser = AmazonOrder::Parser.new(filepath)
      before do
        ensure_fixture_filepath(filepath)
      end

      parser.orders.each do |order|
        current_index = parser.orders.index(order)
        context "for order #{current_index}" do
          order.products.each do |product|
            current_index = order.products.index(product)
            context "for product #{current_index}" do
              it 'has information' do
                expect(product.title).to be_present
                expect(product.path).to match(%r{\A/gp/product/})
                expect(product.content).to be_present
                expect(product.image_url).to match(%r{/images/I/[^.]+\.jpg})
                expect(product.fetched_at).to be_present
              end
            end
          end
        end
      end
    end
  end
end
