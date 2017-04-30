module AmazonOrder
  class Parser
    def initialize(filepath, options = {})
      @filepath = filepath
    end

    def orders
      @orders ||= doc.css(".order").map{|e| AmazonOrder::Parsers::Order.new(e) }
    end

    def doc
      @doc ||= Nokogiri::HTML(body)
    end

    def body
      @body ||= File.read(@filepath)
    end
  end
end
