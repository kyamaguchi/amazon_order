module AmazonOrder
  module Parsers
    class NormalOrder < Base
      ATTRIBUTES = %w[
                     order_placed order_number order_total
                     order_details_path
                   ]

      def order_placed
        @_order_placed ||= parse_date(@node.css('.order-header .a-col-left .a-column')[0].text.split.last)
      end

      def order_number
        @_order_number ||= @node.css('.order-header .a-col-right .a-row')[0].text.split.last
      end

      def order_total
        @_order_total ||= @node.css('.order-header .a-col-left .a-column')[1].text.split.last.gsub(/[^\d\.]/, '').to_f
      end

      def order_details_path
        @_order_details_path ||= @node.css('.order-header .a-col-right .a-row')[1].css('a.a-link-normal')[0].attr('href')
      end

      def order_type
        if @node.css('[id^=Leave-Service-Feedback]').present?
          return :service_order
        elsif @node.css('.shipment').present?
          :shipment_order
        else
          :digital_order
        end
      end

      def products
        @_products ||= @node.css('.a-box:not(.shipment) .a-fixed-left-grid').map { |e| AmazonOrder::Parsers::Product.new(e, fetched_at: fetched_at) }
      end

      def to_hash
        super do |hash|
          hash.merge!(products: products.map(&:to_hash))
        end
      end

    end
  end
end
