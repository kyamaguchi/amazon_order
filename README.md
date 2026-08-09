# AmazonOrder

[![Gem Version](https://badge.fury.io/rb/amazon_order.svg)](https://badge.fury.io/rb/amazon_order)
[![CircleCI](https://circleci.com/gh/kyamaguchi/amazon_order.svg?style=svg)](https://circleci.com/gh/kyamaguchi/amazon_order)

Scrape information of amazon orders from amazon site

##### Fetch Amazon Orders information

![amazon_order_fetch](https://user-images.githubusercontent.com/275284/27861994-1d257558-61be-11e7-9cd3-9abe7fcb0716.gif)

##### Load orders information

![amazon_order_load](https://user-images.githubusercontent.com/275284/27862028-3d19a5be-61be-11e7-8627-1593237c1085.gif)

Recorded with [Recordit](http://recordit.co/)

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'amazon_order'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install amazon_order

## Usage

### Setup

#### Credentials

Create credentials following the instructions of https://github.com/kyamaguchi/amazon_auth  
Use `envchain` or _.env_

```
amazon_auth

envchain amazon ...
# OR
vi .env
```

And `Dotenv.load` or `gem 'dotenv-rails'` may be required when you use this in your app.

### Run

In console

```ruby
require 'amazon_order'
client = AmazonOrder::Client.new(keep_cookie: true, verbose: true, limit: 10)
client.fetch_amazon_orders
# Fetch order-list pages and then each order detail (opt-in)
client = AmazonOrder::Client.new(fetch_order_details: true)
client.fetch_amazon_orders
# Fetch orders of specified year
client.fetch_orders_for_year(year: 2016)

# Fetch all pages of specified year
client = AmazonOrder::Client.new(limit: nil)
client.sign_in_with_retry
client.go_to_amazon_order_page
client.fetch_orders_for_year(year: 2015)
```

Downloaded pages will be stored into `tmp/orders` directory.  
`tmp` comes from `Capybara.save_path`.  

#### Fetch order details

Order details can also be fetched separately after the order-list pages have
been downloaded. The method accepts saved order objects through `orders:` (and
loads all saved order-list pages when it is omitted). Existing, validated
details are skipped by default; pass `force: true` to download them again, or
`freshness:`/`ttl:` in seconds to refresh snapshots older than that duration.
A failed order does not stop the remaining downloads by default
(`continue_on_error: false` makes the first failure abort the operation).

```ruby
client.sign_in_with_retry
client.go_to_amazon_order_page
result = client.fetch_order_details
result = client.fetch_order_details(force: true, continue_on_error: false)
result = client.fetch_order_details(orders: client.load_amazon_orders, freshness: 86_400)

result.entries.each do |entry|
  puts [entry.order_identity, entry.path, entry.status, entry.reason, entry.diagnostic].inspect
end
result.downloaded # entries whose status is :downloaded
result.skipped    # entries whose status is :skipped
result.failed     # entries whose status is :failed
result.success?   # true when no entry failed
```

Fetch failures include a privacy-safe `diagnostic` containing the failing stage
and exception class, but never the exception message or URL. If failures begin
repeating, stop the current run and group them before resuming:

```ruby
result.failed
  .group_by { |entry| [entry.reason, entry.diagnostic] }
  .transform_values(&:size)
# => { [:fetch_failed, "stage=visit error_class=Net::ReadTimeout page_capture=disabled"] => 12 }
```

Stages distinguish navigation (`visit`), page waiting (`wait_for_body`), session
validation (`authentication_check`), temporary saving (`save`), HTML validation
(`validate`), and atomic installation (`install`). Re-running without
`force: true` skips every snapshot saved before the interruption.

An invalid Selenium session is unrecoverable: the browser window has closed or
the driver has discarded it. It is reported as `browser_session_lost` and stops
the loop immediately even when `continue_on_error: true`, avoiding thousands of
identical failures. To enter a debugger at the first failure, install an explicit
local callback before starting:

```ruby
client.options[:capture_detail_failure_page] = true
client.options[:on_detail_fetch_failure] = lambda do |failure, error, session|
  debugger if failure.reason == :browser_session_lost
end
```

With page capture enabled, a best-effort HTML snapshot of the driver's current
page is written under
`orders/details/failures` and the diagnostic reports `page_capture=saved`. A
failure during navigation may therefore capture the preceding page, not the
requested destination. A dead Selenium session cannot provide HTML, so
`InvalidSessionIdError` normally
reports `page_capture=unavailable`; the original exception is still raised and
never hidden by the capture failure. Failure captures contain private page data
and must be protected like normal detail snapshots.

The callback receives the exception and session only in the local process; they
are never serialized or logged. For `InvalidSessionIdError`, Selenium can no
longer inspect the page because the browser session is already gone. The hook is
still useful for inspecting the exception, driver process, and surrounding
state. Restart the client/browser and rerun to resume saved work.

In IRB, assigning a large saved-order array may cause IRB to inspect every
parser object. Parser inspection is intentionally lazy and does not parse every
field, but suppressing the large array output is still recommended:

```ruby
orders = client.load_amazon_orders; nil
result = client.fetch_order_details(orders: orders, continue_on_error: true)
```

This standalone call considers every order loaded from all saved list pages.
Valid saved details are skipped, so the same command safely resumes an
interrupted run without `force: true`.

Audible detail links use a separate `audible.co.jp` authentication session and
are intentionally not visited. They are returned as skipped entries with reason
`unsupported_audible_detail` and logged using only the normal irreversible
order correlation value. This prevents an Audible sign-in redirect from
interrupting the Amazon detail batch:

```ruby
result.skipped.group_by(&:reason).transform_values(&:size)
# => { fresh_snapshot: 3415, unsupported_audible_detail: 12 }
```

For large archives, bound each browser session by the number of newly downloaded
details. Existing snapshots and intentionally skipped Audible entries do not
consume the limit:

```ruby
result = client.fetch_order_details(
  orders: orders,
  continue_on_error: true,
  max_downloads: 250
)

result.stop_reason   # :download_limit_reached when the chunk is full
result.stopped_early? # true when another run is needed
result.complete?      # true after every candidate was considered
```

At the limit the method stops normally before the next navigation. Create a new
client/browser and run the same command again; validated snapshots are skipped,
so each run advances by at most 250 new details. This avoids keeping one Chrome
renderer alive for thousands of navigations while preserving explicit manual
control over authentication and retries.

Load already-saved, validated detail HTML without signing in or making a
network request:

```ruby
load_result = client.load_order_details
# Or avoid reloading list HTML when order objects are already available:
load_result = client.load_order_details(orders: orders)

load_result.loaded.each do |snapshot|
  snapshot.order_identity
  snapshot.path
  snapshot.html # binary HTML bytes
end

# Diagnose missing or invalid snapshots without fetching them:
load_result.failed.group_by(&:reason).transform_values(&:size)
# => { missing_snapshot: 2, truncated_document: 1 }
```

`load_order_details` returns a batch with `loaded`, `failed`, and `success?`.
It is also enumerable over `loaded` snapshots for compatibility. Missing,
truncated, mismatched, or otherwise invalid files appear in `failed` with the
same machine-readable `reason`/`diagnostic` style as fetching. This method does
not call the authentication or browser session APIs. When client logging is
enabled, it logs per-snapshot progress, load/failure state, reason, and the same
short irreversible correlation digest used by fetching; it does not log raw
order identities, paths, or detail URLs.

#### Parse saved order details (offline)

Parsing is an explicit step after loading; it never fetches, authenticates, or
opens a Capybara session:

```ruby
load_result = client.load_order_details(orders: orders)
parse_result = client.parse_order_details(load_result.loaded)
# Stop after the first parse failure if desired:
parse_result = client.parse_order_details(load_result.loaded, continue_on_error: false)

parse_result.orders.each do |detail_order|
  detail_order.order_identity
  detail_order.source_path
  detail_order.items
  detail_order.item_subtotal # displayed 商品の小計
  detail_order.order_total   # displayed 注文合計
  detail_order.charged_total # displayed ご請求額
  detail_order.adjustments   # shipping/handling and discounts
  detail_order.items_total
  detail_order.accounted_total # items plus confirmed adjustments
  detail_order.diagnostics
end
parse_result.failed       # per-snapshot failures with diagnostics
parse_result.success?     # false if any snapshot failed to parse
```

`AmazonOrder::DetailParser.parse(snapshots, continue_on_error: true)` is the
equivalent standalone API. A parsed item exposes `external_line_id`, `asin`,
`title`, `display_amount` (`BigDecimal` or `nil`), `currency`, `quantity`
(positive `Integer` or `nil`), `price_kind`, `price_text`, `price_source`,
`line_status`, `status_text`, `refund_events`, and `diagnostics`. Missing values
are `nil`, not zero. Unknown meanings and states use `:unknown`; the original
display strings are retained separately. Diagnostics expose symbolic `code`, a
non-sensitive `message`, and optional `context`.

Every detail result/model implements `to_hash` and `to_json`. Hash keys and
enum values are strings. Decimals are non-lossy base-10 strings (including
actual zero), dates are ISO 8601 strings, missing values remain `nil`, and
empty refunds remain `[]`. The hash also retains order identity, source path,
line ID, ASIN, original display strings, refund fields, and diagnostics. There
is currently no deserialization API; consumers restore decimal strings with
`BigDecimal(value)` and enum strings with `to_sym` when those Ruby types are
needed.

The confirmed charge-summary rows are parsed separately from product items.
`items_total` sums only row-local unit prices. `accounted_total` sums the
displayed `商品の小計` plus the confirmed `配送料・手数料` and signed `割引`
lines, and can be compared with `charged_total` (`ご請求額`). This distinction
is required when one product row represents multiple units but its confirmed
quantity component is empty: the unit price is preserved and the displayed
subtotal is not reverse-engineered into a quantity. Each summary/adjustment line retains its `kind`, `display_amount`,
`currency`, `label_text`, `amount_text`, `price_source`, and diagnostics.
Missing or duplicate subtotal/order-total/charged-total rows remain `nil` with
an order diagnostic.

To reconcile loaded list totals without converting order-level charges into
fake products:

```ruby
list_by_id = orders.to_h { |order| [order.order_number.to_s, order] }
parse_result.orders.all? do |detail_order|
  list_order = list_by_id[detail_order.order_identity]
  list_order && detail_order.charged_total == BigDecimal(list_order.order_total.to_s)
end
```

For accounting-line summation use `detail_order.amount_lines`, which is the
displayed item-subtotal line plus separately typed adjustments. Do not use
`items.sum(&:display_amount)` as an order total: item values remain the source
`unitPrice`; quantity is not inferred from the subtotal/unit-price ratio, and
shipping and discount are order-level values without a product `lineItemId`.

##### One-command offline audit in IRB

`DetailAudit` combines saved list loading, saved detail loading, detail parsing,
and monetary reconciliation. It never fetches, authenticates, or opens a
browser session:

```ruby
audit = AmazonOrder::DetailAudit.run(client)
audit.pretty_print
audit.success?
audit.coverage_success?
audit.parse_success?
audit.verification_success?
audit.complete_success?
audit.reconciliation_success?
audit.orders
audit.load_result
audit.parse_result
audit.reconciliations
```

Pass an optional directory containing list HTML and its `details` subdirectory:

```ruby
audit = AmazonOrder::DetailAudit.run(
  client,
  directory: ENV.fetch('ORDERS_DIR')
)
audit.pretty_print
```

The directory form temporarily points `Capybara.save_path` at the directory's
parent and uses its basename as `base_dir`, restoring the previous save path
afterward. The compact `summary`/`pretty_print` output contains counts,
diagnostic reason counts, and reconciliation counts. Full parsed values and
per-order decimal totals remain available through `to_hash` and
`reconciliations`; decimals serialize as strings.

The result deliberately separates three questions:

* `coverage_success?`: every list order has a saved detail snapshot;
* `parse_success?`: every loaded snapshot was parsed;
* `verification_success?` (the same monetary result as
  `reconciliation_success?`): every parsed order reconciles.

`complete_success?` and the backward-compatible `success?` require all three.
This means a partial archive can have `verification_success? == true` while
`coverage_success? == false`; verified snapshots reconciled, but the archive is
not complete. The summary reports the same states plus `missing_snapshots`.

Use this audit after every detail-parser or reconciliation change:

```ruby
audit = AmazonOrder::DetailAudit.run(client, directory: ENV['ORDERS_DIR'])
audit.pretty_print
raise 'monetary reconciliation failed' unless audit.reconciliation_success?
```

`reconciliation_success?` can be true even when `success?` is false because
other unsupported layouts can remain in `parse_failures`; it means every parsed,
list-matched order agrees with one of the confirmed displayed detail totals:
`charged_total`, `order_total`, or `item_subtotal`. Amazon's saved-list amount can
represent different members of that set depending on discounts, points, and the
physical/digital layout. `DetailAudit` never requires an unitemized payment
adjustment to be assigned to a product. When the list amount lies strictly
between the displayed item subtotal and charged total, the audit records a
`between_subtotal_and_charged` relation and exposes the two order-level bridge
amounts as `unitemized_merchandise_adjustment` and
`unitemized_payment_adjustment`. This covers promotion/point adjustments that
the detail HTML displays only through its endpoints without pretending that the
unit price or quantity changed. Mismatch entries expose
`available_detail_totals` and select an exactly matching value when one exists.
Parser behavior should be checked from the
same audit's `parse_failures`, `item_diagnostics`, and `order_diagnostics`, not
with ad-hoc IRB snippets.

When reconciliation fails, the same `audit.pretty_print` output includes a
`reconciliation_mismatches` preview with at most 20 entries. The
`reconciliation_mismatches_total` and `reconciliation_mismatches_truncated`
fields report the complete and omitted counts. Each preview entry includes item
count, the selected `detail_total_kind`, list/detail totals,
differences, and order diagnostic codes. It intentionally omits order identity,
source path, ASIN, title, and line ID, so the compact audit output can be used
for follow-up without separate private-data inspection commands.

##### IRB walkthrough after loading snapshots

Given an IRB session that has already run:

```ruby
client = AmazonOrder::Client.new(
  keep_cookie: true,
  verbose: true,
  limit: 10,
  fetch_order_details: true
)
orders = client.load_amazon_orders
result = client.load_order_details(orders: orders)
```

first inspect whether loading the saved files succeeded, independently of
parsing them:

```ruby
result.success?
result.loaded.size
result.failed.map { |failure| [failure.order_identity, failure.reason, failure.diagnostic] }
```

Then explicitly pass only the loaded snapshots to the offline parser:

```ruby
parse_result = client.parse_order_details(result.loaded)

parse_result.success?
parse_result.orders.size
parse_result.failed.map do |failure|
  [failure.order_identity, failure.source_path, failure.reason,
   failure.diagnostics.map(&:to_hash)]
end
```

For a large batch, inspect a compact reason summary instead of printing paths
or order identities:

```ruby
parse_result.failed.group_by(&:reason).transform_values(&:size)
# Example: { unsupported_item_layout: 2, missing_external_line_id: 1 }
```

When parsed orders are available, inspect their items without losing the
snapshot association:

```ruby
parse_result.orders.each do |detail_order|
  puts "order=#{detail_order.order_identity} source=#{detail_order.source_path}"
  detail_order.items.each { |item| pp item.to_hash }
end

# Or serialize the complete batch result:
puts JSON.pretty_generate(parse_result.to_hash)
```

Confirmed normal-order snapshots containing purchased-item rows are parsed.
Snapshots without those rows are reported as `unsupported_item_layout`; this
is a parse-layout failure, not a load or authentication failure.

**Confirmed selector evidence and current limitation.** The checked-in
`spec/fixtures/order_details/normal-sanitized.html` and the privacy-safe,
invented-value `purchased-items-sanitized.html` derived from the confirmed DOM
inventory establish:

* order identity at `div[data-component="orderId"] > span`;
* a shipment boundary at `div[data-component="shipments"]`;
* shipment status at its descendant
  `div[data-component="shipmentStatus"]`, with the displayed shipment text in
  `h4.od-status-message span.a-text-bold`;
* each product-row boundary at
  `div[data-component="shipments"] div[data-component="purchasedItems"]`;
* its stable line ID in the row-local
  `div[data-component="itemConnections"] a[href]` whose path is
  `/your-orders/pop`, using the `lineItemId` query value;
* its ASIN and title in the row-local
  `div[data-component="itemTitle"] a[href]` (`/dp/<ASIN>`), cross-checked with
  the connection's `asin` query value;
* its displayed price in the row-local
  `div[data-component="unitPrice"]`. The component name establishes
  `price_kind == :unit`; repeated identical JPY renderings inside that one
  component are treated as one amount.
* charge-summary rows at
  `div[data-component="chargeSummary"] .a-row.od-line-item-row`, with confirmed
  labels `商品の小計：`, `配送料・手数料：`, `注文合計：`, `割引：`, and
  `ご請求額：`; digital rows also use `この注文の合計:`. Repeated identical label
  spans within one row are deduplicated;
  negative discount text remains a negative `BigDecimal`.

The confirmed `quantity` component is present but empty, so quantity remains
`nil` with a diagnostic; a quantity of one is not inferred. No confirmed
product-line status or refund-event structure is available, so line status is
`:unknown`, status text is `nil`, and refunds are `[]`. Shipment text and the
shipment-level `cancelled` component are not assigned to an individual item.
Cancelled, refunded, partially-refunded, and Audible detail layouts remain
unsupported and are never mapped to purchased. `D01-` snapshots use the same
row-local title, ASIN, and unit-price components, but do not expose a confirmed
stable line identifier. They are parsed with `external_line_id: nil` and an
`external_line_id_unavailable` item diagnostic rather than inventing an ID from
an ASIN, tracking parameter, title, DOM position, or content hash. Digital
`この注文の合計:` rows are treated as the charged total. Their product rows
do not contain the confirmed normal-order stable line identifier, so they are
not misleadingly reported as malformed normal rows. Missing or duplicate
`lineItemId` values in a normal-order snapshot fail the complete order rather
than returning price-bearing successful items.
The `missing_external_line_id` diagnostic context reports only `row_count` and
`missing_line_id_count`; it does not expose row text, ASINs, link values, order
identities, or other private snapshot content.

The repository fixture uses only invented order, line, package, shipment,
ASIN, title, and price values. Real order identities, filenames, product names,
purchase URLs, and other private account data are not copied into fixtures,
specs, documentation, commit messages, or diagnostics.

Standalone `fetch_order_details` verifies the authenticated order-history
session (using the same sign-in retry behavior) before loading saved lists or
requesting any detail page. It stops immediately if authentication still fails.
If authentication expires during the detail loop, fetching also stops even
when `continue_on_error` is enabled; authentication failures are never skipped.

Order-list HTML remains directly under `tmp/orders`; detail HTML is stored in
the separate `tmp/orders/details` directory (both rooted at
`Capybara.save_path`). A detail's deterministic filename is
`order-detail-<SHA-256-of-order-identity>.html`, so the result's
`order_identity` and `path` provide the stable association needed by a later
product-line parser. **These files can contain names, addresses, purchase
history, and other personal information. Store and share them securely.**

A normal run performs no network request when the deterministic file is still
valid. A failed order has no valid final snapshot and is retried on the next
run; successful orders are skipped. `force: true` always refreshes, while
`freshness: seconds` (or its `ttl:` alias) skips a snapshot whose age is less
than or equal to the limit and refreshes an older one. Downloads are written to
a temporary file in the detail directory, flushed, validated, and atomically
renamed. A transport, validation, write, or rename failure therefore preserves
the previous snapshot byte-for-byte. Inspect each entry's symbolic `reason`
and non-sensitive `diagnostic` to distinguish missing links, fetching,
validation, and saving failures.

Detail validation currently covers the confirmed Amazon.co.jp normal-order
component structure only: matching order identity, shipments, and
shipment-status components must all be present in a complete HTML document.
An optional surrounding page-layout element is not required because it can
vary independently of those confirmed detail components. Digital-order,
Audible, and other unconfirmed detail layouts are
not inferred from this structure and fail validation rather than being saved.
Logs contain only status, symbolic reason, progress, and a short irreversible
order correlation digest. Raw order numbers, complete URLs/query parameters,
cookies, tokens, names, addresses, and product titles are not logged.

With the opt-in `fetch_order_details: true`, only orders found in the
order-list pages downloaded by that `fetch_amazon_orders` run are considered.
For example, `limit: 2` fetches details for those two new list pages, not every
historical list page already under `tmp/orders`. Calling `fetch_order_details`
separately continues to use all previously downloaded order-list pages.
With `debug: true`, detail downloads log safe correlation digests and progress
such as `(7/20)`, never raw order numbers or full detail URLs.

`client.sign_in_with_retry` retries up to three times when the underlying `amazon_auth`
sign-in returns false, raises an error, or leaves the browser on an
authentication page. Before each retry it revisits the Amazon origin. Set
`sign_in_attempts` to change the maximum number of attempts (for example,
`sign_in_attempts: 1` to disable retries). Order fetching additionally verifies
that the successfully authenticated browser reaches the order-history page.

Once `fetch_amazon_orders` succeeds, you can load orders information of downloaded pages anytime.
(You don't need to fetch pages with launching browser every time.)

```ruby
orders = client.load_amazon_orders;nil
orders.size

# Sum of order_total
orders.map(&:order_total).sum

# Products
products = orders.map(&:products).flatten;nil
products.size

# Sum of order_total by year
orders.group_by{|o| o.order_placed.strftime('%Y') }.sort_by{|year,_| year }.map{|year,records| puts [year, records.map(&:order_total).sum].inspect };nil
```

#### Example of data

```ruby
console> pp orders.first.to_hash
{"order_placed"=>Wed, 25 Aug 2010,
 "order_number"=>"503-5746373-6335034",
 "order_total"=>2940.0,
 "shipment_status"=>nil,
 "shipment_note"=>nil,
 "order_details_path"=>
  "/gp/your-account/order-details/...",
 "all_products_displayed"=>false,
 :products=>
  [{"title"=>"メタプログラミングRuby",
 ...
}

console> pp products.first.to_hash
{"title"=>"メタプログラミングRuby",
 "path"=>"/gp/product/4048687158/...",
 "content"=>"Paolo Perrotta, 角征典...",
 "image_url"=>
 "https://images-fe.ssl-images-amazon.com/images/I/51TODrMIEnL.jpg"}
```

#### Export csv

```ruby
client.generate_csv
```

#### Options

Limit fetching with number of pages: `client = AmazonOrder::Client.new(limit: 5)`
(`limit: nil` for no limit. default is 5)

Set year range: `client = AmazonOrder::Client.new(year_from: 2012, year_to: 2013)`
(default is Time.current.year)

##### Options of amazon_auth gem

Keep cookies(keep signin): `keep_cookie: true`

Firefox: `driver: :firefox`

Output debug log: `debug: true`

## Notice

This may not work well with amazon.com because I don't have enough data of order pages.
(amazon.co.jp will be OK)

## Development

```ruby
client = AmazonOrder::Client.new(debug: true)
```

### Testing

Test parsing of all your orders pages

```
ORDERS_DIR=/path/to/testapp/orders bundle exec rspec spec/amazon_order/parser_spec.rb
ORDERS_DIR=/path/to/testapp/orders bundle exec rspec spec/amazon_order/parsers/order_spec.rb
ORDERS_DIR=/path/to/testapp/orders bundle exec rspec spec/amazon_order/parsers/product_spec.rb
```

Test downloading of pages

```
$ envchain amazon bundle exec rspec spec/amazon_order/client_spec.rb
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/kyamaguchi/amazon_order.


## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).
