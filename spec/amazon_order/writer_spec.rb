require 'spec_helper'

describe AmazonOrder::Writer do
  describe '#print_orders' do
    let(:writer) { AmazonOrder::Writer.new('spec/fixtures/files/*') }
    describe '#print_orders' do
      it 'has more than 0 orders' do
        expect(writer.print_orders.size).to be > 0
      end
    end
  end

  describe '#print_products' do
    let(:writer) { AmazonOrder::Writer.new('spec/fixtures/files/*') }
    it 'has more than 0 products' do
      expect(writer.print_products.size).to be > 0
    end
  end
end
