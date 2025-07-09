module AmazonOrder
  module Parsers
    class Product < Base
      ATTRIBUTES = %w[
                     title
                     path
                     content
                   ]

      def title
        @_title ||= @node.css('.a-col-right .a-row')[0].text.strip
      end

      def path
        @_path ||= @node.css('.a-col-right .a-row a')[0].attr('href') rescue nil
      end

      def content
        @_content ||= @node.css('.a-col-right .a-row')[1..-1].map(&:text).join.gsub(/\s+/, ' ').strip
      end
    end
  end
end
