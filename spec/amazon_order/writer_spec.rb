require 'spec_helper'

describe AmazonOrder::Writer do
  describe '#print_orders' do
    let(:writer) { AmazonOrder::Writer.new('spec/fixtures/files/*') }
    describe '#print_orders' do
      it 'has more than 0 orders' do
        expect(writer.print_orders.size).to be > 0
      end
      it 'has an order number' do
        expect(writer.print_orders.first[1]).to match(%r{\A[0-9-]+\z}) # order_number
      end
      it 'has an order details path' do
        expect(writer.print_orders.first[3]).to match(%r{\A/gp/your-account/order-details/}) # order_details_path
      end
    end
  end

  describe '#print_products' do
    let(:writer) { AmazonOrder::Writer.new('spec/fixtures/files/*') }
    it 'has more than 0 products' do
      expect(writer.print_products.size).to be > 0
    end
    it 'has a title' do
      expect(writer.print_products.first[0]).to be_present # title
    end
    it 'has a path' do
      expect(writer.print_products.first[1]).to match(%r{\A/gp/product/}) # path
    end
  end
end
