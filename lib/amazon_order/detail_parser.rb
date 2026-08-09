require 'bigdecimal'
require 'date'
require 'json'
require 'nokogiri'
require 'uri'

module AmazonOrder
  # Parses validated, offline order-detail snapshots using confirmed,
  # row-local component boundaries. Physical rows require stable lineItemId
  # values; digital rows explicitly preserve their absence.
  class DetailParser
    ITEM_SELECTOR = 'div[data-component="purchasedItems"]'
    ITEM_LINK_SELECTOR = 'div[data-component="itemTitle"] a[href]'
    ITEM_CONNECTION_SELECTOR = 'div[data-component="itemConnections"] a[href]'
    SUMMARY_ROW_SELECTOR = 'div[data-component="chargeSummary"] .a-row.od-line-item-row'
    DIGITAL_ORDER_ID_PATTERN = /\AD01-/
    SUMMARY_KINDS = {
      '商品の小計：' => :item_subtotal,
      '配送料・手数料：' => :shipping_and_handling,
      '注文合計：' => :order_total,
      'この注文の合計：' => :charged_total,
      '割引：' => :discount,
      'ご請求額：' => :charged_total
    }.freeze

    class Serializable
      def to_json(*arguments)
        to_hash.to_json(*arguments)
      end

      private

      def decimal(value)
        value&.to_s('F')
      end
    end

    class Diagnostic < Serializable
      attr_reader :code, :message, :context

      def initialize(code:, message:, context: nil)
        @code = code.to_sym
        @message = message
        @context = context
      end

      def to_hash
        { 'code' => code.to_s, 'message' => message, 'context' => context }
      end
    end

    class RefundEvent < Serializable
      attr_reader :external_id, :refunded_quantity, :refund_amount, :currency,
        :status, :occurred_on, :status_text, :amount_text

      def initialize(external_id: nil, refunded_quantity: nil, refund_amount: nil,
        currency: nil, status: :unknown, occurred_on: nil, status_text: nil,
        amount_text: nil)
        @external_id = external_id
        @refunded_quantity = refunded_quantity
        @refund_amount = refund_amount
        @currency = currency
        @status = status.to_sym
        @occurred_on = occurred_on
        @status_text = status_text
        @amount_text = amount_text
      end

      def to_hash
        {
          'external_id' => external_id,
          'refunded_quantity' => refunded_quantity,
          'refund_amount' => decimal(refund_amount),
          'currency' => currency,
          'status' => status.to_s,
          'occurred_on' => occurred_on&.iso8601,
          'status_text' => status_text,
          'amount_text' => amount_text
        }
      end
    end

    class Item < Serializable
      attr_reader :external_line_id, :asin, :title, :display_amount, :currency,
        :quantity, :price_kind, :price_text, :price_source, :line_status,
        :status_text, :refund_events, :diagnostics

      def initialize(external_line_id: nil, asin: nil, title: nil,
        display_amount: nil, currency: nil, quantity: nil, price_kind: :unknown,
        price_text: nil, price_source: :order_detail, line_status: :unknown,
        status_text: nil, refund_events: [], diagnostics: [])
        @external_line_id = external_line_id
        @asin = asin&.upcase
        @title = title
        @display_amount = display_amount
        @currency = currency
        @quantity = quantity
        @price_kind = price_kind.to_sym
        @price_text = price_text
        @price_source = price_source.to_sym
        @line_status = line_status.to_sym
        @status_text = status_text
        @refund_events = refund_events.freeze
        @diagnostics = diagnostics.freeze
      end

      def to_hash
        {
          'external_line_id' => external_line_id, 'asin' => asin, 'title' => title,
          'display_amount' => decimal(display_amount), 'currency' => currency,
          'quantity' => quantity, 'price_kind' => price_kind.to_s,
          'price_text' => price_text, 'price_source' => price_source.to_s,
          'line_status' => line_status.to_s, 'status_text' => status_text,
          'refund_events' => refund_events.map(&:to_hash),
          'diagnostics' => diagnostics.map(&:to_hash)
        }
      end
    end

    class AmountLine < Serializable
      attr_reader :kind, :display_amount, :currency, :label_text, :amount_text,
        :price_source, :diagnostics

      def initialize(kind:, display_amount:, currency:, label_text:, amount_text:,
        price_source: :order_detail, diagnostics: [])
        @kind = kind.to_sym
        @display_amount = display_amount
        @currency = currency
        @label_text = label_text
        @amount_text = amount_text
        @price_source = price_source.to_sym
        @diagnostics = diagnostics.freeze
      end

      def to_hash
        {
          'kind' => kind.to_s,
          'display_amount' => decimal(display_amount),
          'currency' => currency,
          'label_text' => label_text,
          'amount_text' => amount_text,
          'price_source' => price_source.to_s,
          'diagnostics' => diagnostics.map(&:to_hash)
        }
      end
    end

    class Order < Serializable
      attr_reader :order_identity, :source_path, :items, :summary_lines,
        :adjustments, :item_subtotal, :order_total, :charged_total, :currency,
        :order_kind, :diagnostics

      def initialize(order_identity:, source_path:, items:, summary_lines: [],
        adjustments: [], item_subtotal: nil, order_total: nil,
        charged_total: nil, currency: nil, order_kind: :physical, diagnostics: [])
        @order_identity = order_identity
        @source_path = source_path
        @items = items.freeze
        @summary_lines = summary_lines.freeze
        @adjustments = adjustments.freeze
        @item_subtotal = item_subtotal
        @order_total = order_total
        @charged_total = charged_total
        @currency = currency
        @order_kind = order_kind.to_sym
        @diagnostics = diagnostics.freeze
      end

      def items_total
        sum_amounts(items)
      end

      def amount_lines
        subtotal_lines = summary_lines.select { |line| line.kind == :item_subtotal }
        subtotal_lines + adjustments
      end

      def accounted_total
        lines = amount_lines
        return items_total if lines.empty?

        sum_amounts(lines)
      end

      def to_hash
        { 'order_identity' => order_identity, 'source_path' => source_path,
          'items' => items.map(&:to_hash),
          'summary_lines' => summary_lines.map(&:to_hash),
          'adjustments' => adjustments.map(&:to_hash),
          'item_subtotal' => decimal(item_subtotal),
          'order_total' => decimal(order_total),
          'charged_total' => decimal(charged_total),
          'currency' => currency,
          'order_kind' => order_kind.to_s,
          'items_total' => decimal(items_total),
          'accounted_total' => decimal(accounted_total),
          'diagnostics' => diagnostics.map(&:to_hash) }
      end

      private

      def sum_amounts(lines)
        amounts = lines.map(&:display_amount)
        return nil if amounts.any?(&:nil?)

        amounts.sum(BigDecimal('0'))
      end
    end

    class Failure < Serializable
      attr_reader :order_identity, :source_path, :diagnostics

      def initialize(order_identity:, source_path:, diagnostics:)
        @order_identity = order_identity
        @source_path = source_path
        @diagnostics = diagnostics.freeze
      end

      def reason
        diagnostics.first&.code
      end

      def to_hash
        { 'order_identity' => order_identity, 'source_path' => source_path,
          'diagnostics' => diagnostics.map(&:to_hash) }
      end
    end

    class BatchResult < Serializable
      attr_reader :orders, :failed

      def initialize(orders:, failed:)
        @orders = orders.freeze
        @failed = failed.freeze
      end

      def success?
        failed.empty?
      end

      def to_hash
        { 'orders' => orders.map(&:to_hash), 'failed' => failed.map(&:to_hash) }
      end
    end

    class << self
      def parse(snapshots, continue_on_error: true)
        orders = []
        failed = []
        Array(snapshots).each do |snapshot|
          outcome = new(snapshot).parse
          if outcome.is_a?(Failure)
            failed << outcome
            break unless continue_on_error
          else
            orders << outcome
          end
        end
        BatchResult.new(orders: orders, failed: failed)
      end
    end

    def initialize(snapshot)
      @snapshot = snapshot
    end

    def parse
      doc = Nokogiri::HTML(snapshot.html.to_s)
      identity_node = doc.at_css('div[data-component="orderId"]')
      return failure(:missing_order_identity, 'The confirmed order identity node is absent') unless identity_node
      return failure(:wrong_order_identity, 'Snapshot identity does not match its HTML') unless
        identity_node.text.strip == snapshot.order_identity.to_s
      digital_order = snapshot.order_identity.to_s.match?(DIGITAL_ORDER_ID_PATTERN)
      return failure(:missing_shipments, 'The confirmed shipments container is absent') unless
        doc.at_css('div[data-component="shipments"]')

      rows = doc.css("div[data-component=\"shipments\"] #{ITEM_SELECTOR}")
      return failure(:unsupported_item_layout, 'The confirmed purchasedItems rows are absent') if rows.empty?

      items = rows.map { |row| parse_item(row, digital_order: digital_order) }
      missing_ids = items.select { |item| item.external_line_id.to_s.empty? }
      return failure(
        :missing_external_line_id,
        'At least one product row has no confirmed lineItemId',
        'row_count' => rows.size,
        'missing_line_id_count' => missing_ids.size
      ) unless digital_order || missing_ids.empty?

      duplicate_ids = items.filter_map(&:external_line_id)
        .group_by(&:itself)
        .select { |_id, grouped| grouped.size > 1 }
        .keys
      return failure(
        :duplicate_external_line_id,
        'Product rows contain duplicate lineItemId values',
        'external_line_ids' => duplicate_ids
      ) unless duplicate_ids.empty?

      summary_lines = parse_summary(doc)
      order_diagnostics = []
      summary = summary_lines.group_by(&:kind)
      item_subtotal = unique_summary_amount(summary, :item_subtotal, order_diagnostics)
      order_total = digital_order ? nil : unique_summary_amount(summary, :order_total, order_diagnostics)
      charged_total = unique_summary_amount(summary, :charged_total, order_diagnostics)
      adjustments = summary_lines.select { |line| [:shipping_and_handling, :discount].include?(line.kind) }
      currency = summary_lines.map(&:currency).compact.uniq.one? ? summary_lines.map(&:currency).compact.first : nil

      item_amounts = items.map(&:display_amount)
      items_total = item_amounts.any?(&:nil?) ? nil : item_amounts.sum(BigDecimal('0'))
      accounted_lines = summary_lines.select { |line| line.kind == :item_subtotal } + adjustments
      accounted_amounts = accounted_lines.map(&:display_amount)
      accounted_total = accounted_amounts.any?(&:nil?) ? nil : accounted_amounts.sum(BigDecimal('0'))
      order_diagnostics << diagnostic(:item_subtotal_mismatch, 'Item unit-price total differs from the displayed item subtotal') if
        items_total && item_subtotal && items_total != item_subtotal
      order_diagnostics << diagnostic(:charged_total_mismatch, 'Displayed item subtotal plus confirmed adjustments differs from the displayed charged total') if
        !digital_order && accounted_total && charged_total && accounted_total != charged_total

      Order.new(
        order_identity: snapshot.order_identity,
        source_path: snapshot.path,
        items: items,
        summary_lines: summary_lines,
        adjustments: adjustments,
        item_subtotal: item_subtotal,
        order_total: order_total,
        charged_total: charged_total,
        currency: currency,
        order_kind: digital_order ? :digital : :physical,
        diagnostics: order_diagnostics
      )
    rescue => error
      failure(:malformed_html, "Detail HTML could not be parsed: #{error.class}")
    end

    private

    attr_reader :snapshot

    def parse_item(row, digital_order: false)
      diagnostics = []
      connection = item_connection(row)
      query = connection ? URI.decode_www_form(URI.parse(connection['href']).query.to_s).to_h : {}
      external_line_id = present(query['lineItemId'])
      diagnostics << diagnostic(
        :external_line_id_unavailable,
        'The digital product row exposes no confirmed stable line identifier'
      ) if digital_order && !external_line_id

      link = row.at_css(ITEM_LINK_SELECTOR)
      link_asin = asin_from_path(link && link['href'])
      query_asin = normalize_asin(query['asin'])
      asin = if link_asin && query_asin && link_asin != query_asin
               diagnostics << diagnostic(:conflicting_asin, 'Product link and item connection contain different ASIN values')
               nil
             else
               link_asin || query_asin
             end

      title = present(link&.text&.gsub(/\s+/, ' ')&.strip)
      diagnostics << diagnostic(:missing_title, 'The confirmed itemTitle link has no title') unless title

      price_text, display_amount, currency = parse_price(row, diagnostics)
      diagnostics << diagnostic(:missing_quantity, 'The confirmed quantity component has no positive integer')
      diagnostics << diagnostic(:unknown_line_status, 'No confirmed product-line status is present')

      Item.new(
        external_line_id: external_line_id,
        asin: asin,
        title: title,
        display_amount: display_amount,
        currency: currency,
        quantity: nil,
        price_kind: :unit,
        price_text: price_text,
        line_status: :unknown,
        status_text: nil,
        refund_events: [],
        diagnostics: diagnostics
      )
    rescue URI::InvalidURIError, ArgumentError
      Item.new(
        diagnostics: [diagnostic(:invalid_item_connection, 'The confirmed item connection URL is invalid')]
      )
    end

    def item_connection(row)
      row.css(ITEM_CONNECTION_SELECTOR).find do |link|
        URI.parse(link['href'].to_s).path == '/your-orders/pop'
      rescue URI::InvalidURIError
        false
      end
    end

    def asin_from_path(href)
      path = URI.parse(href.to_s).path.to_s
      match = path.match(%r{/(?:dp|gp/product)/(?:product/)?([A-Z0-9]{10})(?:/|\z)}i)
      normalize_asin(match && match[1])
    rescue URI::InvalidURIError
      nil
    end

    def normalize_asin(value)
      asin = present(value)&.upcase
      asin if asin&.match?(/\A[A-Z0-9]{10}\z/)
    end

    def parse_price(row, diagnostics)
      node = row.at_css('div[data-component="unitPrice"]')
      text = present(node&.text&.gsub(/\s+/, ' ')&.strip)
      unless text
        diagnostics << diagnostic(:missing_price, 'The confirmed unitPrice component has no displayed price')
        return [nil, nil, nil]
      end

      amounts = text.scan(/￥\s*(?:\d{1,3}(?:,\d{3})+|\d+)(?:\.\d+)?/).map { |value| value.delete('￥, ') }.uniq
      if amounts.size != 1
        diagnostics << diagnostic(:unparseable_price, 'The unitPrice text does not contain one unambiguous JPY amount')
        return [text, nil, nil]
      end

      [text, BigDecimal(amounts.first), 'JPY']
    rescue ArgumentError
      diagnostics << diagnostic(:unparseable_price, 'The unitPrice amount is not a valid decimal')
      [text, nil, nil]
    end

    def parse_summary(doc)
      doc.css(SUMMARY_ROW_SELECTOR).filter_map do |row|
        texts = row.css('span').map { |span| span.text.gsub(/\s+/, ' ').strip }.reject(&:empty?)
        amount_text = texts.find { |text| text.include?('￥') }
        label_text = normalize_summary_label(texts.reject { |text| text.include?('￥') }.uniq.join(' '))
        next unless amount_text

        amount = parse_jpy_amount(amount_text)
        AmountLine.new(
          kind: SUMMARY_KINDS.fetch(label_text, :unknown),
          display_amount: amount,
          currency: amount.nil? ? nil : 'JPY',
          label_text: label_text,
          amount_text: amount_text,
          diagnostics: amount.nil? ? [diagnostic(:unparseable_summary_amount, 'Summary amount is not a valid JPY decimal')] : []
        )
      end
    end

    def normalize_summary_label(text)
      text.to_s.sub(/:\z/, '：')
    end

    def parse_jpy_amount(text)
      match = text.to_s.match(/\A\s*(?<negative>-)?￥\s*(?<amount>\d{1,3}(?:,\d{3})*|\d+)(?:\.\d+)?\s*\z/)
      return nil unless match

      amount = BigDecimal(match[:amount].delete(','))
      match[:negative] ? -amount : amount
    end

    def unique_summary_amount(summary, kind, diagnostics)
      lines = summary.fetch(kind, [])
      if lines.empty?
        diagnostics << diagnostic(:missing_summary_line, "The confirmed #{kind} summary row is absent", 'kind' => kind.to_s)
        return nil
      end
      if lines.size > 1
        diagnostics << diagnostic(:duplicate_summary_line, "The confirmed #{kind} summary row is duplicated", 'kind' => kind.to_s)
        return nil
      end

      lines.first.display_amount
    end

    def present(value)
      value unless value.nil? || value.empty?
    end

    def diagnostic(code, message, context = nil)
      Diagnostic.new(code: code, message: message, context: context)
    end

    def failure(code, message, context = nil)
      Failure.new(
        order_identity: snapshot.respond_to?(:order_identity) ? snapshot.order_identity : nil,
        source_path: snapshot.respond_to?(:path) ? snapshot.path : nil,
        diagnostics: [diagnostic(code, message, context)]
      )
    end
  end
end
