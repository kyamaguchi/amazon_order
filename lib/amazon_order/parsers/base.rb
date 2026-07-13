module AmazonOrder
  module Parsers
    class ParseError < StandardError; end

    class Base
      attr_accessor :fetched_at, :source_path

      def initialize(node, options = {})
        @node = node
        @fetched_at = options[:fetched_at]
        @source_path = options[:source_path]
        @containing_object = options[:containing_object]
      end

      def inspect
        "#<#{self.class.name}:#{self.object_id} #{self.to_hash}>"
      end

      def to_hash
        hash = {}
        self.class::ATTRIBUTES.each do |f|
          hash[f] = send(f)
        end
        yield(hash) if block_given?
        hash
      end

      def values
        self.class::ATTRIBUTES.map{|a| send(a) }
      end

      def required_node(selector, index: 0, context:)
        @node.css(selector)[index] || raise_parse_error(selector: selector, index: index, context: context)
      end

      def parse_date(date_text)
        begin
          Date.parse(date_text)
        rescue ArgumentError => e
          m = date_text.match(/\A(?<year>\d{4})年(?<month>\d{1,2})月(?<day>\d{1,2})日\z/)
          Date.new(m[:year].to_i, m[:month].to_i, m[:day].to_i)
        end
      end

      private

      def raise_parse_error(selector:, index:, context:)
        message = [
          "#{self.class.name} failed to parse #{context}",
          "selector=#{selector.inspect}",
          "index=#{index}",
          "source_path=#{source_path.inspect}",
          "node=#{short_node_snapshot}"
        ].compact.join(', ')

        raise ParseError, message
      end

      def short_node_snapshot
        snapshot = if @node.respond_to?(:to_html)
          @node.to_html
        else
          @node.text
        end

        snapshot.to_s.gsub(/\s+/, ' ').strip[0, 500]
      end
    end
  end
end
