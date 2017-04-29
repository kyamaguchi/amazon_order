module AmazonOrder
  class Parser
    class Order
      ATTRIBUTES = %w[
                     order_placed order_number order_total
                     shipment_status shipment_note
                     order_details_path
                     all_products_displayed
                   ]

      def initialize(node)
        @node = node
      end

      def inspect
        "#<#{self.class.name}:#{self.object_id} #{self.to_hash}>"
      end

      def order_placed
        @_order_placed ||= parse_date(@node.css('.order-info .a-col-left .a-column')[0].css('.value').text.strip)
      end

      def order_number
        @_order_number ||= @node.css('.order-info .a-col-right .a-row')[0].css('.value').text.strip
      end

      def order_total
        @_order_total ||= @node.css('.order-info .a-col-left .a-column')[1].css('.value').text.strip.gsub(/[^\d\.]/,'')
      end

      def shipment_status
        # class names like "shipment-is-delivered" in '.shipment' node may be useful
        @_shipment_status ||= @node.css('.shipment').present? ? @node.css('.shipment .shipment-top-row .a-row')[0].text.strip : nil
      end

      def shipment_note
        @_shipment_note ||= @node.css('.shipment').present? ? @node.css('.shipment .shipment-top-row .a-row')[1].text.strip : nil
      end

      def order_details_path
        @_order_details_path ||= @node.css('.order-info .a-col-right .a-row')[1].css('a.a-link-normal')[0].attr('href')
      end

      def all_products_displayed
        @_all_products_displayed ||= @node.css('.a-box.order-info ~ .a-box .a-col-left .a-row').last.css('.a-link-emphasis').present?
      end

      def products
        @_products ||= @node.css('.a-box.order-info ~ .a-box .a-col-left .a-row')[0].css('.a-fixed-left-grid').map{|e| Product.new(e) }
      end


      def to_hash
        hash = {}
        ATTRIBUTES.each do |f|
          hash[f] = send(f)
        end
        hash.merge!(products: products.map(&:to_hash))
        hash
      end

      def parse_date(date_text)
        begin
          Date.parse(date_text)
        rescue ArgumentError => e
          m = date_text.match(/\A(?<year>\d{4})年(?<month>\d{1,2})月(?<day>\d{1,2})日\z/)
          Date.new(m[:year].to_i, m[:month].to_i, m[:day].to_i)
        end
      end
    end

    class Product
      ATTRIBUTES = %w[
                     title
                     path
                     content
                     image_url
                   ]

      def initialize(node)
        @node = node
      end

      def inspect
        "#<#{self.class.name}:#{self.object_id} #{self.to_hash}>"
      end

      def title
        @_title ||= @node.css('.a-col-right .a-row')[0].text.strip
      end

      def path
        @_path ||= @node.css('.a-col-right .a-row a')[0].attr('href')
      end

      def content
        @_content ||= @node.css('.a-col-right .a-row')[1..-1].map(&:text).join.gsub(/\s+/, ' ').strip
      end

      def image_url
        @_image_url ||= get_original_image_url(@node.css('.a-col-left img')[0].attr('src'))
      end


      def to_hash
        hash = {}
        ATTRIBUTES.each do |f|
          hash[f] = send(f)
        end
        hash
      end

      def get_original_image_url(url)
        parts = url.split('/')
        (parts[0..-2] + [parts.last.split('.').values_at(0,-1).join('.')]).join('/')
      end
    end

    def initialize(filepath, options = {})
      @filepath = filepath
    end

    def orders
      @orders ||= doc.css(".order").map{|e| Order.new(e) }
    end

    def doc
      @doc ||= Nokogiri::HTML(body)
    end

    def body
      @body ||= File.read(@filepath)
    end
  end
end
