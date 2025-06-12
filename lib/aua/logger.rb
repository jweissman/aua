require "logger"

module Aua
  class Logger < ::Logger
    using Rainbow

    LHS_WIDTH = 12

    def format_message(_severity, _timestamp, progname, msg)
      lhs = [
        progname.to_s.rjust(LHS_WIDTH - 8)
      ].join(" ")
      [lhs.rjust(LHS_WIDTH), msg.to_s.strip]
        .join(" | ")
        .tap do |formatted|
        formatted << "\n"
      end
    end

    def self.default(progname = "aura", outlet: self.outlet) = @default ||= new(outlet, level:, progname:)
    def self.level = ENV.fetch("AUA_LOG_LEVEL", "info").to_sym

    # Returns the appropriate output stream for logging.
    # If testing, it uses a file; otherwise, it uses $stdout.
    #
    # @return [IO] The output stream for logging.
    def self.outlet
      # puts "Setup outlet for #{Aua.testing? ? 'testing' : 'production'}"
      $stderr # unless Aua.testing?
    end
  end

  def self.logger = @logger ||= Logger.default

  def self.logger=(logger)
    @logger = logger
  end
end
