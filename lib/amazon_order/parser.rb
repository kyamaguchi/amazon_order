module AmazonOrder
  class Parser
    attr_accessor :fetched_at

    def initialize(filepath, options = {})
      @filepath = filepath

      @fetched_at = if (m = File.basename(@filepath).match(/\D(\d{14})/))
        Time.strptime(m[1], '%Y%m%d%H%M%S')
      else
        File.ctime(@filepath)
      end
    end

    def orders
      @orders ||= doc.css(".order").map{|e| AmazonOrder::Parsers::Order.new(e, fetched_at: fetched_at) }
    end

    def doc
      @doc ||= Nokogiri::HTML(body)
    end

    def body
      @body ||= File.read(@filepath)
    end
  end
end
