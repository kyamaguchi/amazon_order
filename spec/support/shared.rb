TARGET_DIR = ENV['ORDERS_DIR'].presence || 'spec/fixtures/files'

def ensure_fixture_filepath(path)
  pending("Put your html in #{path} for testing") unless path && File.exist?(path)
  path
end
