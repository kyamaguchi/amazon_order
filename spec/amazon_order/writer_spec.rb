require 'spec_helper'

describe AmazonOrder::Writer do
  describe '#print_orders' do
    it "prints data of orders" do
      writer = AmazonOrder::Writer.new('spec/fixtures/files/*')
      expect(writer.print_orders.size).to be > 0
      expect(writer.print_orders.first[1]).to match(%r{\A[0-9-]+\z}) # order_number
      expect(writer.print_orders.first[5]).to match(%r{\A/gp/your-account/order-details/}) # order_details_path
    end
  end

  describe '#print_products' do
    it "prints data of products" do
      writer = AmazonOrder::Writer.new('spec/fixtures/files/*')
      expect(writer.print_products.size).to be > 0
      expect(writer.print_products.first[0]).to be_present # title
      expect(writer.print_products.first[1]).to match(%r{\A/gp/product/}) # path
    end
  end
end
