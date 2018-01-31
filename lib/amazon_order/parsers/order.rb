module AmazonOrder
  module Parsers
    class Order < Base
      ATTRIBUTES = %w[
                     order_placed order_number order_total
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
        @_order_total ||= @node.css('.order-info .a-col-left .a-column')[1].css('.value').text.strip.gsub(/[^\d\.]/, '').to_f
      end

      def order_details_path
        @_order_details_path ||= @node.css('.order-info .a-col-right .a-row')[1].css('a.a-link-normal')[0].attr('href')
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

      def shipments
        @_shipments ||= @node.css('.shipment')
          .map do |shipment|
          AmazonOrder::Parsers::Shipment.new(shipment,
                                             containing_object: self,
                                             fetched_at: fetched_at)
        end
      end

      def products
        @products ||= shipment_products + digital_products
      end

      def shipment_products
        @shipment_products ||= shipments.flat_map(&:products)
      end

      def digital_products
        @_products ||= @node.css('.a-box:not(.shipment) .a-fixed-left-grid').map { |e| AmazonOrder::Parsers::Product.new(e, fetched_at: fetched_at) }
      end

      # might be broken now that orders have multiple shipments
      def all_products_displayed
        @_all_products_displayed ||= @node.css('.a-box.order-info ~ .a-box .a-col-left .a-row').last.css('.a-link-emphasis').present?
      end

      def to_hash
        super do |hash|
          hash.merge!(products: products.map(&:to_hash))
        end
      end

    end
  end
end
