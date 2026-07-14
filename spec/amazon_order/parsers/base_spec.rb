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

    it 'removes blank lines from the node HTML snapshot' do
      node_with_blank_lines = Nokogiri::HTML.fragment(<<~HTML)
        <div class="order-card">

          <span class="present">ok</span>

        </div>
      HTML
      parser = described_class.new(node_with_blank_lines)

      expect {
        parser.required_node('.missing', context: 'order_total')
      }.to raise_error(AmazonOrder::Parsers::ParseError) { |error|
        html = error.message[/node_html=(.*)\z/m, 1]

        expect(html).to include('<div class="order-card">')
        expect(html).to include('<span class="present">ok</span>')
        expect(html).not_to include("\n\n")
      }
    end
  end
end
