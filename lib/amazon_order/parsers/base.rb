module AmazonOrder
  module Parsers
    class Base
      attr_accessor :fetched_at

      def initialize(node, options = {})
        @node = node
        @fetched_at = options[:fetched_at]
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

      def parse_date(date_text)
        begin
          Date.parse(date_text)
        rescue ArgumentError => e
          m = date_text.match(/\A(?<year>\d{4})年(?<month>\d{1,2})月(?<day>\d{1,2})日\z/)
          Date.new(m[:year].to_i, m[:month].to_i, m[:day].to_i)
        end
      end
    end
  end
end
