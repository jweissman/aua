# frozen_string_literal: true

require "rspec"
require "debug"
require "aua"

# Load custom matchers
require_relative "support/be_aua_matcher"

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.before do
    Aua.testing = true

    outlet = Thread.current[:logger] ||= begin
      FileUtils.mkdir_p("log")
      File.open("log/aura.log", "w")
    rescue StandardError => e
      warn "Failed to open log file: #{e.message}"
      $stderr
    end

    Aua.logger = Aua::Logger.default("spec", outlet:)

    # Aua.logger.info "Starting tests at #{Time.now.utc.iso8601}"
  end
end
