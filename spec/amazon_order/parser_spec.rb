require 'spec_helper'

describe AmazonOrder::Parser do
  TARGET_DIR = ENV['ORDERS_DIR'].presence || 'spec/fixtures/files'

  def find_fixture_filepath(name)
    path = File.join(TARGET_DIR, name || '')
    pending("Put your html in #{path} for testing") unless name.present? && File.exists?(path)
    path
  end

  context 'with single file' do
    before do
      filepath = find_fixture_filepath(Dir.entries('spec/fixtures/files').select{|f| f =~ /html/ }.last)
      @parser = AmazonOrder::Parser.new(filepath)
    end

    it "finds selector of order" do
      expect(@parser.body).to be_present
      expect(@parser.doc.css(".order").size).to be > 0
    end

    it "finds orders" do
      expect(@parser.orders.size).to be > 0
      expect(@parser.orders.first).to be_a(AmazonOrder::Parser::Order)
    end
  end

  describe 'orders' do
    Dir.entries(TARGET_DIR).select{|f| f =~ /html/ }.each do |file|
      context "with file (#{file})" do
        before do
          @parser = AmazonOrder::Parser.new(find_fixture_filepath(file))
        end

        it "has information" do
          order = @parser.orders.last
          expect(order.order_placed).to be_a(Date)
          expect(order.order_number).to match(/\A[D\d][\d\-]+\z/)
          expect(order.order_total).to match(/\A[\d\.]+\z/)
          expect(order.order_details_path).to match(%r{\A/gp/})

          expect(order.products.size).to be > 0
          product = order.products.first
          expect(product.title).to be_present
          expect(product.path).to match(%r{\A/gp/product/})
          expect(product.content).to be_present
          expect(product.image_url).to match(%r{/images/I/[^.]+\.jpg})
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

    it "generate data as csv files", csv: true do
      require 'csv'
      FileUtils.mkdir_p('tmp')

      data = {'orders' => [], 'products' => []}
      Dir.entries(TARGET_DIR).select{|f| f =~ /html/ }.each do |file|
        puts "    Parsing #{file}"
        parser = AmazonOrder::Parser.new(find_fixture_filepath(file))
        data['orders'] += parser.orders.map(&:values)
        data['products'] += parser.orders.map(&:products).flatten.map(&:values)
      end

      %w[orders products].each do |resource|
        csv_file = "tmp/#{resource}#{Time.current.strftime('%Y%m%d%H%M%S')}.csv"
        puts "    Writing #{csv_file}"
        CSV.open(csv_file, 'wb') do |csv|
          data[resource].each{|r| csv << r }
        end
      end
    end
  end

  describe '#get_original_image_url' do
    it "removes image options from url" do
      parser = AmazonOrder::Parser::Product.new(nil)
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
