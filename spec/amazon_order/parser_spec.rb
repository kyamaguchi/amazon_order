require 'spec_helper'

describe AmazonOrder::Parser do
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

  describe '#orders' do
    Dir.glob("#{TARGET_DIR}/*html").each do |filepath|
      context "with file (#{filepath})" do
        parser = AmazonOrder::Parser.new(filepath)
        before do
          ensure_fixture_filepath(filepath)
        end

        it "has information" do
          expect(parser.fetched_at).to be_present
        end
      end
    end
  end
end
