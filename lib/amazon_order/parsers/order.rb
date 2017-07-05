module AmazonOrder
  module Parsers
    class Order < Base
      ATTRIBUTES = %w[
                     order_placed order_number order_total
                     shipment_status shipment_note
                     order_details_path
                     all_products_displayed
                   ]

      def order_placed
        @_order_placed ||= parse_date(@node.css('.order-info .a-col-left .a-column')[0].css('.value').text.strip)
      end

      def order_number
        @_order_number ||= @node.css('.order-info .a-col-right .a-row')[0].css('.value').text.strip
      end

      def order_total
        @_order_total ||= @node.css('.order-info .a-col-left .a-column')[1].css('.value').text.strip.gsub(/[^\d\.]/,'').to_f
      end

      def shipment_status
        # class names like "shipment-is-delivered" in '.shipment' node may be useful
        @_shipment_status ||= @node.css('.shipment .shipment-top-row').present? ? @node.css('.shipment .shipment-top-row .a-row')[0].text.strip : nil
      end

      def shipment_note
        @_shipment_note ||= @node.css('.shipment .shipment-top-row').present? ? @node.css('.shipment .shipment-top-row .a-row')[1].text.strip : nil
      end

      def order_details_path
        @_order_details_path ||= @node.css('.order-info .a-col-right .a-row')[1].css('a.a-link-normal')[0].attr('href')
      end

      def all_products_displayed
        @_all_products_displayed ||= @node.css('.a-box.order-info ~ .a-box .a-col-left .a-row').last.css('.a-link-emphasis').present?
      end

      def products
        @_products ||= @node.css('.a-box.order-info ~ .a-box .a-col-left .a-row')[0].css('.a-fixed-left-grid').map{|e| AmazonOrder::Parsers::Product.new(e, fetched_at: fetched_at) }
      end


      def to_hash
        super do |hash|
          hash.merge!(products: products.map(&:to_hash))
        end
      end
    end
  end
end
