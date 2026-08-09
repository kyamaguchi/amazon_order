require 'bigdecimal'
require 'json'

module AmazonOrder
  # Runs the complete saved-list -> saved-detail -> offline-parse -> monetary
  # reconciliation workflow without fetching, authenticating, or opening a
  # browser session.
  class DetailAudit
    Reconciliation = Struct.new(
      :order_identity, :list_total, :items_total, :item_subtotal, :accounted_total,
      :order_total, :charged_total, :item_count, :order_kind, keyword_init: true
    ) do
      def items_match_subtotal?
        !items_total.nil? && items_total == item_subtotal
      end

      def detail_total_kind
        selected_detail_total&.first
      end

      def detail_total
        selected_detail_total&.last
      end

      def accounted_matches_detail_total?
        matches_any_detail_total?(accounted_total)
      end

      def list_matches_detail_total?
        matches_any_detail_total?(list_total) || list_bridges_detail_totals?
      end

      def list_detail_relation
        return :exact if matches_any_detail_total?(list_total)
        return :between_subtotal_and_charged if list_bridges_detail_totals?

        :unmatched
      end

      def to_hash
        {
          'order_identity' => order_identity,
          'list_total' => decimal(list_total),
          'items_total' => decimal(items_total),
          'item_subtotal' => decimal(item_subtotal),
          'accounted_total' => decimal(accounted_total),
          'order_total' => decimal(order_total),
          'charged_total' => decimal(charged_total),
          'order_kind' => order_kind.to_s,
          'detail_total_kind' => detail_total_kind&.to_s,
          'detail_total' => decimal(detail_total),
          'list_detail_relation' => list_detail_relation.to_s,
          'unitemized_merchandise_adjustment' => list_bridges_detail_totals? ?
            decimal_difference(list_total, item_subtotal) : nil,
          'unitemized_payment_adjustment' => list_bridges_detail_totals? ?
            decimal_difference(charged_total, list_total) : nil,
          'available_detail_totals' => detail_totals.to_h do |kind, amount|
            [kind.to_s, decimal(amount)]
          end,
          'item_count' => item_count,
          'accounted_matches_detail_total' => accounted_matches_detail_total?,
          'list_matches_detail_total' => list_matches_detail_total?
        }
      end

      private

      def decimal(value)
        value&.to_s('F')
      end

      def detail_totals
        [
          [:charged_total, charged_total],
          [:order_total, order_total],
          [:item_subtotal, item_subtotal]
        ].reject { |_kind, amount| amount.nil? }
          .uniq { |_kind, amount| amount }
      end

      def matches_any_detail_total?(value)
        !value.nil? && detail_totals.any? { |_kind, amount| amount == value }
      end

      def selected_detail_total
        detail_totals.find { |_kind, amount| amount == list_total } ||
          ([:list_total_bridge, list_total] if list_bridges_detail_totals?) ||
          detail_totals.find { |_kind, amount| amount == accounted_total } ||
          detail_totals.first
      end

      def list_bridges_detail_totals?
        return false if list_total.nil? || charged_total.nil? || item_subtotal.nil?

        lower, upper = [charged_total, item_subtotal].minmax
        list_total > lower && list_total < upper
      end

      def decimal_difference(left, right)
        return nil if left.nil? || right.nil?

        decimal(left - right)
      end
    end

    class Result
      attr_reader :orders, :load_result, :parse_result, :reconciliations,
        :directory

      def initialize(orders:, load_result:, parse_result:, reconciliations:,
        directory:)
        @orders = orders.freeze
        @load_result = load_result
        @parse_result = parse_result
        @reconciliations = reconciliations.freeze
        @directory = directory
      end

      def coverage_success?
        load_result.success?
      end

      def parse_success?
        parse_result.success?
      end

      def verification_success?
        reconciliation_success?
      end

      def complete_success?
        coverage_success? && parse_success? && verification_success?
      end

      def success?
        complete_success?
      end

      # Monetary verification is intentionally separate from batch success:
      # unsupported layouts may remain while every supported order reconciles.
      def reconciliation_success?
        !reconciliations.empty? &&
          reconciliations.size == parse_result.orders.size &&
          reconciliations.all?(&:accounted_matches_detail_total?) &&
          reconciliations.all?(&:list_matches_detail_total?)
      end

      def summary
        {
          'directory' => directory,
          'list_orders' => orders.size,
          'loaded_snapshots' => load_result.loaded.size,
          'missing_snapshots' => load_result.failed.count { |failure| failure.reason == :missing_snapshot },
          'coverage_success' => coverage_success?,
          'load_failures' => reason_counts(load_result.failed),
          'parsed_orders' => parse_result.orders.size,
          'parsed_items' => parse_result.orders.sum { |order| order.items.size },
          'parse_success' => parse_success?,
          'parse_failures' => reason_counts(parse_result.failed),
          'compared_orders' => reconciliations.size,
          'unmatched_parsed_orders' => parse_result.orders.size - reconciliations.size,
          'items_match_subtotal' => reconciliations.count(&:items_match_subtotal?),
          'accounted_match_detail_total' => reconciliations.count(&:accounted_matches_detail_total?),
          'list_match_detail_total' => reconciliations.count(&:list_matches_detail_total?),
          'list_total_relations' => reconciliations.group_by(&:list_detail_relation)
            .transform_values(&:size).transform_keys(&:to_s),
          'reconciliation_failures' => reconciliations.count do |entry|
            !entry.accounted_matches_detail_total? || !entry.list_matches_detail_total?
          end,
          'reconciliation_mismatches_total' => reconciliation_mismatches.size,
          'reconciliation_mismatches' => reconciliation_mismatches.first(20),
          'reconciliation_mismatches_truncated' => [reconciliation_mismatches.size - 20, 0].max,
          'reconciliation_success' => reconciliation_success?,
          'verification_success' => verification_success?,
          'item_diagnostics' => diagnostic_counts(
            parse_result.orders.flat_map(&:items).flat_map(&:diagnostics)
          ),
          'order_diagnostics' => diagnostic_counts(
            parse_result.orders.flat_map(&:diagnostics)
          ),
          'complete_success' => complete_success?,
          'success' => success?
        }
      end

      def to_hash
        summary.merge(
          'reconciliations' => reconciliations.map(&:to_hash),
          'parsed' => parse_result.to_hash
        )
      end

      def to_json(*arguments)
        to_hash.to_json(*arguments)
      end

      def pretty_print(io = $stdout)
        io.puts(JSON.pretty_generate(summary))
        self
      end

      private

      def reason_counts(entries)
        entries.group_by(&:reason).transform_values(&:size).transform_keys(&:to_s)
      end

      def diagnostic_counts(diagnostics)
        diagnostics.group_by(&:code).transform_values(&:size).transform_keys(&:to_s)
      end

      def reconciliation_mismatches
        details = parse_result.orders.to_h { |order| [order.order_identity, order] }
        reconciliations.filter_map do |entry|
          next if entry.accounted_matches_detail_total? && entry.list_matches_detail_total?

          detail = details[entry.order_identity]
          {
            'item_count' => entry.item_count,
            'items_total' => decimal(entry.items_total),
            'item_subtotal' => decimal(entry.item_subtotal),
            'accounted_total' => decimal(entry.accounted_total),
            'order_total' => decimal(entry.order_total),
            'charged_total' => decimal(entry.charged_total),
            'detail_total_kind' => entry.detail_total_kind&.to_s,
            'detail_total' => decimal(entry.detail_total),
            'list_detail_relation' => entry.list_detail_relation.to_s,
            'available_detail_totals' => entry.to_hash['available_detail_totals'],
            'list_total' => decimal(entry.list_total),
            'accounted_difference' => decimal_difference(entry.accounted_total, entry.detail_total),
            'list_difference' => decimal_difference(entry.list_total, entry.detail_total),
            'order_diagnostics' => detail ? detail.diagnostics.map { |diagnostic| diagnostic.code.to_s } : []
          }
        end
      end

      def decimal(value)
        value&.to_s('F')
      end

      def decimal_difference(left, right)
        return nil if left.nil? || right.nil?

        decimal(left - right)
      end

    end

    class << self
      def run(client, directory: nil)
        new(client, directory: directory).run
      end
    end

    def initialize(client, directory: nil)
      @client = client
      @directory = directory && File.expand_path(directory)
    end

    def run
      with_source do |source_client|
        orders = source_client.load_amazon_orders
        load_result = source_client.load_order_details(orders: orders)
        parse_result = source_client.parse_order_details(load_result.loaded)
        Result.new(
          orders: orders,
          load_result: load_result,
          parse_result: parse_result,
          reconciliations: reconcile(orders, parse_result.orders),
          directory: directory
        )
      end
    end

    private

    attr_reader :client, :directory

    def with_source
      return yield(client) unless directory

      previous_save_path = Capybara.save_path
      source_client = AmazonOrder::Client.new(
        client.options.merge(base_dir: File.basename(directory))
      )
      Capybara.save_path = File.dirname(directory)
      yield(source_client)
    ensure
      Capybara.save_path = previous_save_path if directory
    end

    def reconcile(orders, detail_orders)
      list_by_identity = orders.to_h { |order| [order.order_number.to_s, order] }
      detail_orders.filter_map do |detail_order|
        list_order = list_by_identity[detail_order.order_identity]
        next unless list_order

        Reconciliation.new(
          order_identity: detail_order.order_identity,
          list_total: BigDecimal(list_order.order_total.to_s),
          items_total: detail_order.items_total,
          item_subtotal: detail_order.item_subtotal,
          accounted_total: detail_order.accounted_total,
          order_total: detail_order.order_total,
          charged_total: detail_order.charged_total,
          item_count: detail_order.items.size,
          order_kind: detail_order.order_kind
        )
      end
    end
  end
end
