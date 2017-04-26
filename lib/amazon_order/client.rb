module AmazonOrder
  class Client
    attr_accessor :session

    def initialize(options = {})
      @options = options
      begin
        @client = AmazonAuth::Client.new(@options)
      rescue => e
        puts "Please setup credentials of amazon_auth gem with folloing its instruction."
        raise e
      end
      extend(AmazonAuth::SessionExtension)
    end

    def session
      @session ||= @client.session
    end

    def fetch_amazon_orders
      sign_in
      go_to_amazon_order_page
      fetch_orders_for_year
    end

    def sign_in
      @client.sign_in
    end

    def go_to_amazon_order_page
      link = links_for('a').find{|link| link =~ %r{/order-history} }
      session.visit link
    end

    def fetch_orders_for_year(options = {})
      year = options.fetch(:year, Time.current.year)
      switch_year(year)
      save_page_for(year, current_page_node.try!(:text))
      while (node = next_page_node) do
        session.visit node.attr('href')
        save_page_for(year, current_page_node.text)
      end
    end

    def switch_year(year)
      return true if year.to_i == selected_year
      session.first('.order-filter-dropdown .a-icon-dropdown').click
      session.all('.a-popover-wrapper .a-dropdown-link').find{|e| e.text.gsub(/\D+/,'').to_i == year.to_i }.click
      sleep 2
      puts "Year:#{year} -> #{number_of_orders}"
    end

    def save_page_for(year, page)
      puts "Saving year:#{year} page:#{page}"
      path = ['order', year.to_s, "p#{page}", Time.current.strftime('%Y%m%d%H%M%S')].join('-') + '.html'
      session.save_page(File.join('orders', path))
    end

    def selected_year
      wait_for_selector('#orderFilter')
      doc.css('#orderFilter option').find{|o| !o.attr('selected').nil? }.attr('value').gsub(/\D+/,'').to_i
    end

    def number_of_orders
      doc.css('#controlsContainer .num-orders').text.strip
    end

    def current_page_node
      wait_for_selector('.a-pagination .a-selected')
      doc.css('.a-pagination .a-selected a').first
    end

    def next_page_node
      wait_for_selector('.a-pagination .a-selected')
      doc.css('.a-pagination .a-selected ~ .a-normal').css('a').first
    end
  end
end
