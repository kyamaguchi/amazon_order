require 'spec_helper'

# This will fail unless you have environment variables set, see readme

describe AmazonOrder::Client do
  let!(:client) { AmazonOrder::Client.new() }
  # needs output of amazon_auth in environment, see readme
  xit 'initializes' do
    expect { client }.not_to raise_error
  end

  # very slow
  xit '#fetch_amazon_orders' do
    expect { client.fetch_amazon_orders }.not_to raise_error
  end

  # expects valid files in /tmp
  # TODO: make this work with fixtures instead
  xit 'can generate csv' do
    client.load_amazon_orders;nil
    expect { client.generate_csv }.not_to raise_error
  end
end
