require 'uri'

module AmazonOrder
  class Client
    class AuthenticationError < StandardError; end

    include AmazonAuth::CommonExtension

    attr_accessor :session, :options

    def initialize(options = {})
      @options = options
      @client = AmazonAuth::Client.new(@options)
      extend(AmazonAuth::SessionExtension)
    end

    def base_dir
      options.fetch(:base_dir, 'orders')
    end

    def year_from
      options.fetch(:year_from, Time.current.year)
    end

    def year_to
      options.fetch(:year_to, Time.current.year)
    end

    def limit
      options.fetch(:limit, 5)
    end

    def session
      @session ||= @client.session
    end

    def fetch_amazon_orders
      sign_in
      go_to_amazon_order_page
      year_to.to_i.downto(year_from.to_i) do |year|
        fetch_orders_for_year(year: year)
      end
      fetch_order_details if options.fetch(:fetch_order_details, false)
    end

    # Fetches each order's detail page once. Order numbers, rather than URLs,
    # identify orders because Amazon adds non-stable reference parameters to
    # detail links.
    def fetch_order_details(fetch_options = {})
      force = fetch_options.fetch(:force, options.fetch(:force_order_details, false))
      continue_on_error = fetch_options.fetch(
        :continue_on_error,
        options.fetch(:continue_on_detail_error, true)
      )
      origin = order_history_origin
      seen = {}

      load_amazon_orders.each do |order|
        order_number = order.order_number.to_s
        path = order.order_details_path.to_s
        next if order_number.empty? || path.empty? || seen[order_number]
        seen[order_number] = true

        filename_order_number = sanitized_order_number(order_number)
        if !force && detail_already_saved?(filename_order_number)
          log "Skipping saved order detail: order=#{order_number} url=#{path}"
          next
        end

        url = absolute_order_details_url(path, origin)
        begin
          session.visit(url)
          wait_for_selector('body')
          if authentication_page?
            raise "authentication page was displayed"
          end

          filename = [
            'order-detail', filename_order_number,
            Time.current.strftime('%Y%m%d%H%M%S%L')
          ].join('-') + '.html'
          session.save_page(File.join(base_dir, 'details', filename))
        rescue => e
          log "Failed to fetch order detail: order=#{order_number} url=#{url} error=#{e.message}"
          raise unless continue_on_error
        end
      end
    end

    def load_amazon_orders
      orders = []
      Dir.glob(file_glob_pattern).each do |filepath|
        parser = AmazonOrder::Parser.new(filepath)
        log "Loading #{filepath} with #{parser.orders.size} orders"
        orders += parser.orders
      end
      orders.sort_by{|o| -o.fetched_at.to_i }.uniq(&:order_number)
    end

    def file_glob_pattern
      File.join(Capybara.save_path, base_dir, '*html')
    end

    def generate_csv
      writer.generate_csv
    end

    def writer
      @_writer ||= AmazonOrder::Writer.new(file_glob_pattern)
    end

    def sign_in
      @client.sign_in
      return unless authentication_page?

      raise AuthenticationError,
        "Amazon sign-in did not complete (current_url=#{session.current_url})"
    end

    def go_to_amazon_order_page
      if doc.css('.cvf-account-switcher').present?
        log "Account switcher page was displayed"
        session.first('.cvf-account-switcher-profile-details').click
        wait_for_selector('#nav-main') # Wait for page loading
      end
      link = links_for('a').find{|link| link =~ %r{/order-history} }
      if link.present?
        session.visit link
        @order_history_origin = url_origin(session.current_url)
      else
        log "Link for order history wasn't found in #{session.current_url}"
      end
    end

    def fetch_orders_for_year(options = {})
      year = options.fetch(:year, Time.current.year)
      if switch_year(year)
        save_page_for(year, current_page_node.try!(:text))
        while (node = next_page_node) do
          session.visit node.attr('href')
          save_page_for(year, current_page_node.text)
          break if limit && limit <= current_page_node.text.to_i
        end
      end
    end

    def switch_year(year)
      return true if year.to_i == selected_year
      session.first('.a-dropdown-container .a-dropdown-prompt').click
      option = session.all('.a-popover-wrapper .a-dropdown-link').find{|e| e.text.gsub(/\D+/,'').to_i == year.to_i }
      return false if option.nil?
      option.click
      sleep 2
      log "Year:#{year} -> #{number_of_orders}"
      true
    rescue => e
      puts "#{e.message}\n#{e.backtrace.join("\n")}"
      false
    end

    def save_page_for(year, page)
      log "Saving year:#{year} page:#{page}"
      path = ['order', year.to_s, "p#{page}", Time.current.strftime('%Y%m%d%H%M%S')].join('-') + '.html'
      session.save_page(File.join(base_dir, path))
    end

    def selected_year
      wait_for_selector('#time-filter, #orderFilter')
      doc.css('#time-filter option, #orderFilter option').find{|o| !o.attr('selected').nil? }.attr('value').gsub(/\D+/,'').to_i
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

    private

    def order_history_origin
      @order_history_origin ||= url_origin(session.current_url)
      raise ArgumentError, 'The order history page URL is required to resolve relative detail links' if @order_history_origin.nil?
      @order_history_origin
    end

    def url_origin(url)
      uri = URI.parse(url.to_s)
      return nil unless uri.is_a?(URI::HTTP) && uri.host
      "#{uri.scheme}://#{uri.host}#{uri.port == uri.default_port ? '' : ":#{uri.port}"}"
    rescue URI::InvalidURIError
      nil
    end

    def absolute_order_details_url(path, origin)
      uri = URI.parse(path)
      uri.is_a?(URI::HTTP) ? uri.to_s : URI.join("#{origin}/", path).to_s
    end

    def sanitized_order_number(order_number)
      sanitized = order_number.to_s.encode('UTF-8', invalid: :replace, undef: :replace, replace: '')
                              .gsub(/[^0-9A-Za-z._-]+/, '_')
                              .gsub(/\A[._-]+|[._-]+\z/, '')
      sanitized.empty? ? 'unknown' : sanitized
    end

    def detail_already_saved?(filename_order_number)
      pattern = File.join(
        Capybara.save_path, base_dir, 'details',
        "order-detail-#{filename_order_number}-*.html"
      )
      Dir.glob(pattern).any?
    end

    def authentication_page?
      session.current_url.to_s.match?(%r{/(?:ap/)?signin(?:[/?]|$)|/ap/cvf/}) ||
        doc.css('form[name="signIn"], #ap_email, #ap_password').any?
    end
  end
end
