require 'spec_helper'

describe AmazonOrder::Writer do
  describe '#print_orders' do
    let(:writer) { AmazonOrder::Writer.new('spec/fixtures/files/*') }
    describe '#print_orders' do
      it 'has more than 0 orders' do
        expect(writer.print_orders.size).to be > 0
      end
      it 'has an order number' do
        expect(writer.print_orders.map{|x| x[1] }).to all(satisfy {|v| v =~ %r{\AD?[0-9-]+\z} } )
      end
      it 'has an order details path' do
        expect(writer.print_orders.map{|x| x[3] }).to all(satisfy {|v| v =~ %r{\A/gp/(your-account/order-details|digital/your-account/order-summary)} } )
      end
    end
  end

  describe '#print_products' do
    let(:writer) { AmazonOrder::Writer.new('spec/fixtures/files/*') }
    it 'has more than 0 products' do
      expect(writer.print_products.size).to be > 0
    end
    it 'has a title' do
      expect(writer.print_products.map{|x| x[0] }).to all(satisfy(&:present?))
    end
    it 'has a path' do
      expect(writer.print_products.map{|x| x[1] }).to all(satisfy {|v| v =~ %r{\A/gp/product/} } )
    end
  end
end
