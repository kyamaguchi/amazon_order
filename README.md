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
client.sign_in
client.go_to_amazon_order_page
client.fetch_orders_for_year(year: 2015)
```

Downloaded pages will be stored into `tmp/orders` directory.  
`tmp` comes from `Capybara.save_path`.  

Order details can also be fetched separately after the order-list pages have
been downloaded. Existing details are skipped by order number by default; pass
`force: true` to download them again. A failed order is logged and does not
stop the remaining downloads by default (`continue_on_error: false` makes the
first failure abort the operation).

```ruby
client.sign_in
client.go_to_amazon_order_page
client.fetch_order_details
client.fetch_order_details(force: true, continue_on_error: false)
```

Detail HTML files are stored under `tmp/orders/details` (relative to
`Capybara.save_path`). **These files can contain names, addresses, purchase
history, and other personal information. Store and share them securely.**

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
