module AmazonOrder
  class Writer
    def initialize(file_glob_pattern, options = {})
      @file_glob_pattern = file_glob_pattern
      @output_dir = options.fetch(:output_dir, 'tmp')
    end

    def print_orders
      data['orders']
    end

    def print_products
      data['products']
    end

    def generate_csv
      require 'csv'
      FileUtils.mkdir_p(@output_dir)
      %w[orders products].map do |resource|
        next if data[resource].blank?
        csv_file = "#{@output_dir}/#{resource}#{Time.current.strftime('%Y%m%d%H%M%S')}.csv"
        puts "    Writing #{csv_file}"
        CSV.open(csv_file, 'wb') do |csv|
          csv << attributes_for(resource)
          data[resource].each { |r| csv << r }
        end
        csv_file
      end
    end

    private

    def data
      @_data ||= begin
        data = {'orders' => [], 'products' => []}
        Dir.glob(@file_glob_pattern).each do |filepath|
          puts "    Parsing #{filepath}"
          parser = AmazonOrder::Parser.new(filepath)
          data['orders'] += parser.orders.map(&:values)
          data['products'] += parser.orders.map(&:products).flatten.map(&:values)
        end
        data
      end
    end

    def attributes_for(resource)
      case resource
      when 'orders'
        AmazonOrder::Parsers::Order::ATTRIBUTES
      when 'products'
        AmazonOrder::Parsers::Product::ATTRIBUTES
      end
    end
  end
end
