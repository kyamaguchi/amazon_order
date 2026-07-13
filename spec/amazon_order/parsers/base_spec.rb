require 'spec_helper'

RSpec.describe AmazonOrder::Parsers::Base do
  let(:node) { Nokogiri::HTML.fragment('<div class="order-card"><span class="present">ok</span></div>') }
  let(:parser) { described_class.new(node, source_path: 'spec/fixtures/source.html') }

  describe '#required_node' do
    it 'returns the node matching selector and index' do
      expect(parser.required_node('.present', context: 'title').text).to eq('ok')
    end

    it 'raises ParseError with parser context when the node is missing' do
      expect {
        parser.required_node('.missing', index: 2, context: 'order_total')
      }.to raise_error(AmazonOrder::Parsers::ParseError) { |error|
        expect(error.message).to include('AmazonOrder::Parsers::Base')
        expect(error.message).to include('order_total')
        expect(error.message).to include('selector=".missing"')
        expect(error.message).to include('index=2')
        expect(error.message).to include('source_path="spec/fixtures/source.html"')
        expect(error.message).to include('order-card')
      }
    end
  end
end
