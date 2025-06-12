# frozen_string_literal: true

require "rspec"
require "debug"
require "aua"

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

    Aua.logger = Thread.current[:logger] ||= begin
      FileUtils.mkdir_p("log")
      outlet = File.open("log/aura.log", "w")
      Aua::Logger.default("spec", outlet:)
    rescue StandardError => e
      warn "Failed to open log file: #{e.message}"
      $stderr
    end
  end
end
