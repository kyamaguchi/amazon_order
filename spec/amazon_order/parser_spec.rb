require 'spec_helper'
require 'tempfile'

describe AmazonOrder::Parser do
  context 'with single file' do
    before do
      filepath = ensure_fixture_filepath(Dir.glob("#{TARGET_DIR}/*html").last)
      @parser = AmazonOrder::Parser.new(ensure_fixture_filepath(filepath))
    end

    it "finds selector of order" do
      expect(@parser.body).to be_present
      expect(@parser.doc.css(".order-card").size).to be > 0
    end

    it "finds orders" do
      expect(@parser.orders.size).to be > 0
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
          expect(parser.orders.size).to be > 0
          # expect(parser.orders.size).to eq 10 # When checks exact count
        end
      end
    end
  end

  context 'with a canceled normal order that has no order total' do
    let(:tempfile) { Tempfile.new(['canceled-order', '.html']) }
    let(:filepath) do
      tempfile.write(<<~HTML)
        <div class="order-card js-order-card">
          <div class="a-box-group a-spacing-base">
            <div class="a-box a-color-offset-background order-header">
              <div class="a-box-inner">
                <div class="a-fixed-right-grid-col a-col-left">
                  <div class="a-row">
                    <div class="a-column a-span12 a-span-last">
                      <span class="a-color-secondary a-text-caps">注文日</span>
                      <span class="a-size-base a-color-secondary aok-break-word">2020年7月14日</span>
                    </div>
                  </div>
                </div>
                <div class="a-fixed-right-grid-col a-col-right">
                  <div class="a-row a-size-mini">
                    <div class="yohtmlc-order-id">
                      <span class="a-color-secondary a-text-caps">注文番号</span>
                      <span class="a-color-secondary" dir="ltr">624-2345678-3456789</span>
                    </div>
                  </div>
                  <div class="a-row"></div>
                </div>
              </div>
            </div>
            <div class="a-box delivery-box">
              <div class="a-box-inner">
                <div class="yohtmlc-shipment-status-primaryText">
                  <span class="a-size-medium delivery-box__primary-text a-text-bold">キャンセル済み</span>
                </div>
                <span class="delivery-box__secondary-text">商品はキャンセルされました。 これらの商品については請求されていません。</span>
              </div>
            </div>
          </div>
        </div>
      HTML
      tempfile.close
      tempfile.path
    end

    after do
      tempfile.close!
    end

    it 'ignores the order instead of raising when totals are read later' do
      expect(described_class.new(filepath).orders).to eq([])
    end
  end

end
