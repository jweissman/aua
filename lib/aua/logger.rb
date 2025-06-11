module Aua
  class Logger < ::Logger
    using Rainbow

    LHS_WIDTH = 12

    def format_message(severity, timestamp, progname, msg)
      lhs = [
        progname.to_s.rjust(LHS_WIDTH - 8)
      ].join(" ")
      [lhs.rjust(LHS_WIDTH), msg.to_s.strip]
        .join(" | ")
        .tap do |formatted|
        formatted << "\n"
      end
    end

    def self.default(progname = "aura") = @default ||= new(outlet, level:, progname:)
    def self.level = ENV.fetch("AUA_LOG_LEVEL", "info").to_sym

    # Returns the appropriate output stream for logging.
    # If testing, it uses a file; otherwise, it uses $stdout.
    #
    # @return [IO] The output stream for logging.
    def self.outlet
      return $stderr unless Aua.testing?

      warn "Creating log file at log/aura.log" if Aua.testing?
      FileUtils.mkdir_p("log") unless Dir.exist?("log")
      begin
        File.open("log/aura.log", "w") do |file|
          file.sync = true # Ensure writes are immediate
          file
        end
      rescue StandardError => e
        warn "Failed to open log file: #{e.message}"
        warn "Failed to open log file: #{e.message}"
        $stderr
      end
    end
  end

  def self.logger = @logger ||= Logger.default
end
