require 'uri'
require 'digest'
require 'fileutils'
require 'tempfile'
require 'pathname'

module AmazonOrder
  class Client
    class AuthenticationError < StandardError; end
    class DetailFetchError < StandardError; end
    class DetailSaveError < StandardError; end

    DetailResult = Struct.new(:order_identity, :path, :status, :reason, :diagnostic, keyword_init: true)
    DetailSnapshot = Struct.new(:order_identity, :path, :html, keyword_init: true)
    DetailLoadBatchResult = Struct.new(:loaded, :failed, keyword_init: true) do
      include Enumerable
      def each(&block); loaded.each(&block); end
      def size; loaded.size; end
      def empty?; loaded.empty?; end
      def success?; failed.empty?; end
    end
    DetailBatchResult = Struct.new(:entries, :stop_reason, keyword_init: true) do
      def downloaded; entries.select { |entry| entry.status == :downloaded }; end
      def skipped; entries.select { |entry| entry.status == :skipped }; end
      def failed; entries.select { |entry| entry.status == :failed }; end
      def success?; failed.empty?; end
      def complete?; stop_reason.nil?; end
      def stopped_early?; !complete?; end
    end

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
      ensure_order_history_session
      fetched_page_paths = year_to.to_i.downto(year_from.to_i).flat_map do |year|
        fetch_orders_for_year(year: year)
      end
      if options.fetch(:fetch_order_details, false)
        fetch_order_details(orders: parse_amazon_orders(fetched_page_paths))
      end
    end

    # Fetches each order's detail page once. Order numbers, rather than URLs,
    # identify orders because Amazon adds non-stable reference parameters to
    # detail links.
    def fetch_order_details(fetch_options = {})
      ensure_order_history_session
      force = fetch_options.fetch(:force, options.fetch(:force_order_details, false))
      freshness = fetch_options.fetch(:freshness, fetch_options.fetch(:ttl, options[:order_details_freshness]))
      continue_on_error = fetch_options.fetch(
        :continue_on_error,
        options.fetch(:continue_on_detail_error, true)
      )
      max_downloads = fetch_options.fetch(
        :max_downloads,
        options[:max_detail_downloads]
      )
      max_downloads = max_downloads.to_i if max_downloads
      max_downloads = nil unless max_downloads&.positive?
      orders = fetch_options.fetch(:orders) { load_amazon_orders }.to_a
      origin = order_history_origin
      candidates = {}
      conflicted = {}
      results = []
      stop_reason = nil
      downloads = 0

      orders.each_with_index do |order, index|
        progress = "(#{index + 1}/#{orders.size})"
        order_number = order.order_number.to_s
        path = order.order_details_path.to_s
        if order_number.empty?
          results << detail_result(nil, nil, :failed, :missing_identity)
          raise DetailFetchError, 'missing_identity' unless continue_on_error
          next
        end
        next if conflicted[order_number]
        final_path = detail_path(order_number)
        if path.empty?
          results << detail_result(order_number, final_path, :failed, :missing_link)
          raise DetailFetchError, 'missing_link' unless continue_on_error
          next
        end
        begin
          url = absolute_order_details_url(path, origin)
        rescue URI::InvalidURIError
          results << detail_result(order_number, final_path, :failed, :invalid_url)
          raise DetailFetchError, 'invalid_url' unless continue_on_error
          next
        end
        if audible_detail_url?(url)
          results << detail_result(order_number, final_path, :skipped, :unsupported_audible_detail)
          safe_detail_log(
            'Skipping Audible order detail', progress, order_number,
            :unsupported_audible_detail
          )
          next
        end
        if candidates.key?(order_number)
          if candidates[order_number][:link_identity] != detail_link_identity(url)
            candidates.delete(order_number)
            conflicted[order_number] = true
            results << detail_result(order_number, final_path, :failed, :conflicting_links)
            raise DetailFetchError, 'conflicting_links' unless continue_on_error
          end
          next
        end
        candidates[order_number] = {
          url: url,
          path: final_path,
          link_identity: detail_link_identity(url),
          progress: progress
        }
      end

      candidates.each do |order_number, candidate|
        url = candidate[:url]
        final_path = candidate[:path]
        progress = candidate[:progress]
        if max_downloads && downloads >= max_downloads
          stop_reason = :download_limit_reached
          safe_detail_log(
            'Stopping order detail batch', progress, order_number,
            stop_reason
          )
          break
        end
        stage = :prepare
        begin
          detail_directory = File.expand_path(File.dirname(final_path))
          FileUtils.mkdir_p(detail_directory)
          lock_path = "#{final_path}.lock"
          File.open(lock_path, File::RDWR | File::CREAT, 0600) do |lock|
            lock.flock(File::LOCK_EX)
            if !force && valid_detail_file?(final_path, order_number) && fresh_detail?(final_path, freshness)
              safe_detail_log('Skipping saved order detail', progress, order_number, :fresh_snapshot)
              results << detail_result(order_number, final_path, :skipped, :fresh_snapshot)
              next
            end

            safe_detail_log('Fetching order detail', progress, order_number, :download)
            stage = :visit
            session.visit(url)
            stage = :wait_for_body
            wait_for_selector('body')
            stage = :authentication_check
            raise AuthenticationError, 'authentication page was displayed' if authentication_page?

            stage = :save
            temporary = Tempfile.new(['.order-detail-', '.tmp'], detail_directory)
            temporary_path = temporary.path
            temporary.close
            begin
              relative_temporary_path = Pathname.new(temporary_path).relative_path_from(
                Pathname.new(Capybara.save_path).expand_path
              ).to_s
              begin
                session.save_page(relative_temporary_path)
                File.open(temporary_path, 'r+') { |file| file.flush; file.fsync }
              rescue => e
                raise DetailSaveError, e.class.name
              end
              stage = :validate
              validation = validate_detail_html(File.binread(temporary_path), order_number)
              raise DetailFetchError, validation unless validation == :valid
              begin
                stage = :install
                File.rename(temporary_path, final_path)
              rescue => e
                raise DetailSaveError, e.class.name
              end
              results << detail_result(order_number, final_path, :downloaded, :downloaded)
              downloads += 1
              safe_detail_log('Saved order detail', progress, order_number, :downloaded)
            ensure
              FileUtils.rm_f(temporary_path) if temporary_path
            end
          end
        rescue => e
          reason = detail_failure_reason(e)
          page_capture = capture_detail_failure_page(order_number)
          diagnostic = detail_failure_diagnostic(e, stage, page_capture: page_capture)
          failure = detail_result(order_number, final_path, :failed, reason, diagnostic: diagnostic)
          results << failure
          safe_detail_log(
            'Failed to fetch order detail', progress, order_number, reason,
            diagnostic: diagnostic
          )
          notify_detail_fetch_failure(failure, e)
          raise if unrecoverable_detail_fetch_error?(e) || !continue_on_error
        end
      end
      DetailBatchResult.new(entries: results, stop_reason: stop_reason)
    end

    def load_amazon_orders
      parse_amazon_orders(Dir.glob(file_glob_pattern))
    end

    # Loads already-saved, valid detail snapshots without authenticating or
    # making a network request. Order objects provide the identity-to-digest
    # mapping because raw identities are intentionally absent from filenames.
    def load_order_details(load_options = {})
      orders = load_options.fetch(:orders) { load_amazon_orders }.to_a
      seen = {}
      loaded = []
      failed = []

      orders.each_with_index do |order, index|
        progress = "(#{index + 1}/#{orders.size})"
        order_identity = order.order_number.to_s
        if order_identity.empty?
          failed << detail_result(nil, nil, :failed, :missing_identity)
          safe_detail_log('Failed to load order detail', progress, nil, :missing_identity)
          next
        end
        next if seen[order_identity]
        seen[order_identity] = true

        path = detail_path(order_identity)
        unless File.file?(path)
          failed << detail_result(order_identity, path, :failed, :missing_snapshot)
          safe_detail_log('Failed to load order detail', progress, order_identity, :missing_snapshot)
          next
        end
        begin
          html = File.binread(path)
        rescue SystemCallError
          failed << detail_result(order_identity, path, :failed, :load_failed)
          safe_detail_log('Failed to load order detail', progress, order_identity, :load_failed)
          next
        end
        validation = validate_detail_html(html, order_identity)
        unless validation == :valid
          failed << detail_result(order_identity, path, :failed, validation)
          safe_detail_log('Failed to load order detail', progress, order_identity, validation)
          next
        end

        loaded << DetailSnapshot.new(
          order_identity: order_identity,
          path: path,
          html: html
        )
        safe_detail_log('Loaded order detail', progress, order_identity, :loaded)
      end
      DetailLoadBatchResult.new(loaded: loaded, failed: failed)
    end

    # Explicitly parses already-loaded snapshots. This method performs no
    # authentication, browser-session access, file IO, or network requests.
    def parse_order_details(snapshots, parse_options = {})
      AmazonOrder::DetailParser.parse(
        snapshots,
        continue_on_error: parse_options.fetch(:continue_on_error, true)
      )
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

    def sign_in_with_retry
      max_attempts = options.fetch(:sign_in_attempts, 3).to_i
      max_attempts = 1 if max_attempts < 1

      1.upto(max_attempts) do |attempt|
        begin
          result = @client.sign_in
          # amazon_auth returns false when it cannot find signInSubmit, even
          # when a stored session has already taken the browser to an
          # authenticated Amazon page.  The page is more authoritative than
          # that implementation-detail return value.
          return true unless authentication_page?
          raise AuthenticationError,
            "Amazon sign-in did not complete (result=#{result.inspect}, current_url=#{session.current_url})"
        rescue => e
          log "Amazon sign-in attempt #{attempt}/#{max_attempts} failed: #{e.message}"
          raise AuthenticationError, e.message if attempt == max_attempts

          retry_url = url_origin(session.current_url)
          log "Retrying Amazon sign-in from #{retry_url}"
          session.visit("#{retry_url}/") if retry_url
        end
      end
    end

    def go_to_amazon_order_page
      return true if order_history_page?

      if doc.css('.cvf-account-switcher').present?
        log "Account switcher page was displayed"
        session.first('.cvf-account-switcher-profile-details').click
        wait_for_selector('#nav-main') # Wait for page loading
      end
      link = links_for('a').find{|link| link =~ %r{/order-history} }
      if link.present?
        session.visit link
        @order_history_origin = url_origin(session.current_url)
        return order_history_page?
      else
        log "Link for order history wasn't found in #{session.current_url}"
      end
      false
    end

    def fetch_orders_for_year(options = {})
      year = options.fetch(:year, Time.current.year)
      saved_page_paths = []
      if switch_year(year)
        saved_page_paths << save_page_for(year, current_page_node.try!(:text))
        while (node = next_page_node) do
          session.visit node.attr('href')
          saved_page_paths << save_page_for(year, current_page_node.text)
          break if limit && limit <= current_page_node.text.to_i
        end
      end
      saved_page_paths
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
      File.join(Capybara.save_path, base_dir, path)
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

    def ensure_order_history_session
      return true if order_history_page?

      sign_in_and_open_order_history
    end

    def sign_in_and_open_order_history
      sign_in_with_retry
      return true if go_to_amazon_order_page

      raise AuthenticationError,
        "Amazon order history was not reached (current_url=#{session.current_url})"
    end

    def order_history_page?
      session.current_url.to_s.match?(%r{/(?:your-orders/orders|gp/(?:your-account|css)/order-history)}) &&
        !authentication_page?
    end

    def parse_amazon_orders(filepaths)
      orders = filepaths.flat_map do |filepath|
        parser = AmazonOrder::Parser.new(filepath)
        log "Loading #{filepath} with #{parser.orders.size} orders"
        parser.orders
      end
      orders.sort_by{|o| -o.fetched_at.to_i }.uniq(&:order_number)
    end

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
      resolved = uri.is_a?(URI::HTTP) ? uri : URI.join("#{origin}/", path)
      raise URI::InvalidURIError, 'detail URL must use HTTP(S)' unless resolved.is_a?(URI::HTTP) && resolved.host
      resolved.to_s
    end

    def audible_detail_url?(url)
      host = URI.parse(url).host.to_s.downcase
      host == 'audible.co.jp' || host.end_with?('.audible.co.jp')
    rescue URI::InvalidURIError
      false
    end

    def detail_path(order_number)
      digest = Digest::SHA256.hexdigest(order_number.to_s)
      File.join(Capybara.save_path, base_dir, 'details', "order-detail-#{digest}.html")
    end

    # Amazon varies tracking reference parameters between otherwise identical
    # links. They do not participate in the order/link consistency check.
    def detail_link_identity(url)
      uri = URI.parse(url)
      query = URI.decode_www_form(uri.query.to_s).reject { |key, _value| key == 'ref' || key == 'ref_' }
      uri.query = query.empty? ? nil : URI.encode_www_form(query.sort)
      uri.fragment = nil
      uri.to_s
    end

    def validate_detail_html(html, order_number)
      return :empty_document if html.to_s.strip.empty?
      return :truncated_document unless html.match?(%r{</body>\s*</html>\s*\z}i)
      detail_doc = Nokogiri::HTML(html)
      identity = detail_doc.at_css('div[data-component="orderId"]')
      return :missing_order_identity unless identity
      return :wrong_order_identity unless identity.text.strip == order_number.to_s
      return :missing_shipments unless detail_doc.at_css('div[data-component="shipments"]')
      return :missing_shipment_status unless detail_doc.at_css('div[data-component="shipmentStatus"]')
      :valid
    end

    def valid_detail_file?(path, order_number)
      File.file?(path) && validate_detail_html(File.binread(path), order_number) == :valid
    rescue SystemCallError
      false
    end

    def fresh_detail?(path, freshness)
      return true if freshness.nil?
      (detail_now - File.mtime(path)) <= freshness.to_f
    end

    def detail_now
      clock = options[:clock]
      clock ? clock.call : Time.now
    end

    def detail_result(identity, path, status, reason, diagnostic: reason.to_s)
      DetailResult.new(
        order_identity: identity,
        path: path,
        status: status,
        reason: reason,
        diagnostic: diagnostic
      )
    end

    def detail_failure_reason(error)
      return :authentication_required if error.is_a?(AuthenticationError)
      return :browser_session_lost if invalid_browser_session_error?(error)
      return error.message.to_sym if error.is_a?(DetailFetchError)
      return :save_failed if error.is_a?(DetailSaveError) || error.is_a?(SystemCallError) || error.is_a?(IOError)
      :fetch_failed
    end

    def unrecoverable_detail_fetch_error?(error)
      error.is_a?(AuthenticationError) || invalid_browser_session_error?(error)
    end

    def invalid_browser_session_error?(error)
      error.class.name == 'Selenium::WebDriver::Error::InvalidSessionIdError'
    end

    def notify_detail_fetch_failure(failure, error)
      callback = options[:on_detail_fetch_failure]
      callback.call(failure, error, session) if callback
    end

    def detail_failure_diagnostic(error, stage, page_capture: :disabled)
      error_class = if error.is_a?(DetailSaveError) && !error.message.to_s.empty?
                      error.message
                    else
                      error.class.name
                    end
      "stage=#{stage} error_class=#{error_class} page_capture=#{page_capture}"
    end

    def capture_detail_failure_page(identity)
      return :disabled unless options[:capture_detail_failure_page]

      correlation = Digest::SHA256.hexdigest(identity.to_s)[0, 12]
      relative_path = File.join(base_dir, 'details', 'failures', "detail-failure-#{correlation}.html")
      session.save_page(relative_path)
      :saved
    rescue
      :unavailable
    end

    def safe_detail_log(action, progress, identity, reason, diagnostic: nil)
      correlation = Digest::SHA256.hexdigest(identity.to_s)[0, 12]
      suffix = diagnostic ? " diagnostic=#{diagnostic}" : ''
      log "#{action} #{progress}: order_ref=#{correlation} reason=#{reason}#{suffix}"
    end

    def authentication_page?
      current_url = session.current_url.to_s
      return true if current_url.match?(%r{/(?:ap/)?signin(?:[/?]|$)|/ap/cvf/|/ax/claim(?:[/?]|$)})

      # Amazon's normal home page can contain hidden sign-in inputs, so DOM
      # selectors are not reliable once the browser has a concrete non-auth
      # URL. Keep the DOM fallback only for drivers that cannot expose a URL.
      current_url.empty? && doc.css('form[name="signIn"], #ap_email, #ap_password').any?
    end
  end
end
