module AmazonOrder
  module Parsers
    class Shipment < Base
      ATTRIBUTES = %w[
                     shipment_status
                     shipment_note
                   ]

      # TODO shipment_date

      def order
        @containing_object
      end

      def shipment_status
        # class names like "shipment-is-delivered" in '.shipment' node may be useful
        @_shipment_status ||= @node.css('.shipment-top-row').present? ? @node.css('.shipment .shipment-top-row .a-row')[0].text.strip : nil
      end

      def shipment_note
        @_shipment_note ||= case order.order_type
        when :shipment_order
          @node.css('.shipment-top-row').present? ? @node.css('.shipment .shipment-top-row .a-row')[1].text.strip : nil
        when :service_order
          nil
        when :digital_order
          nil
        end
      end


      def products
        @_products ||= @node.css('.a-fixed-left-grid').map { |e| AmazonOrder::Parsers::Product.new(e, fetched_at: fetched_at) }
      end

    end
  end
end
