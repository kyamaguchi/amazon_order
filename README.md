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
