# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'amazon_order/version'

Gem::Specification.new do |spec|
  spec.name          = "amazon_order"
  spec.version       = AmazonOrder::VERSION
  spec.authors       = ["Kazuho Yamaguchi"]
  spec.email         = ["kzh.yap@gmail.com"]

  spec.summary       = %q{Scrape information of amazon orders}
  spec.description   = %q{Scrape information of amazon orders}
  spec.homepage      = "https://github.com/kyamaguchi/amazon_order"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/}) || f.start_with?('.')
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_runtime_dependency "amazon_auth", "~> 0.9.0"
  spec.add_development_dependency "bundler"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "rspec"
  spec.add_development_dependency "byebug"
  spec.add_development_dependency "pry-rescue"
  spec.add_development_dependency "pry-stack_explorer"
end
