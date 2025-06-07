require "net/http"
require "json"
require "digest"
require "time"

module Aua
  # The LLM module expresses the integration with a Language Model (LLM) provider.
  # It provides a way to interact with the LLM API, send prompts, and receive responses.
  #
  # @example
  #   Aua::LLM.chat.ask("What is the capital of France?")
  #
  # @see Aua::LLM::Provider
  # @see Aua::LLM::Provider::Response
  # @see Aua::LLM::Chat
  module LLM
    # The Provider class is responsible for interacting with the LLM provider API.
    # It handles requests and responses, including error handling and response parsing.
    #
    # @example
    #   provider = Aua::LLM::Provider.new(base_uri: "http://localhost:1234/v1")
    #   response = provider.request(prompt: "Hello, world!")
    #   puts response.message
    class Provider
      class Error < StandardError; end

      class Cache
        def key(*args)
          key_content = args.join(":")
          puts "Cache key: #{key_content}" if Aua.testing?
          Digest::SHA256.hexdigest(
            key_content + Aua.configuration.model + Aua.configuration.base_uri
          )
        end

        def fetch(key, &)
          @cache ||= {}
          # @cache[key] ||= yield
          if @cache.key?(key)
            puts "Cache hit for key: #{key}" if Aua.testing?
            @cache[key]
          else
            val = yield
            puts "Storing value in cache for key: #{key} => #{val}" if Aua.testing?
            @cache[key] = val
            if @cache_miss_lambda
              puts "Executing cache miss lambda for key: #{key}" if Aua.testing?
              @cache_miss_lambda.call(key, val) # @cache[key])
            end
            @cache[key]
          end
        end

        def with_cache(*, &)
          # value(key(*), &)
          the_key = key(*)
          puts "Using cache key: #{the_key}" if Aua.testing?
          fetch(the_key, &)
        rescue StandardError => e
          puts "Cache error: #{e.message}" if Aua.testing?
          @cache_miss_lambda.call(the_key, nil) if @cache_miss_lambda
          nil
        end

        def hydrate(file_path)
          return unless File.exist?(file_path)

          @cache ||= {}

          File.open(file_path, "r") do |file|
            file.each_line do |line|
              entry = JSON.parse(line, symbolize_names: true)
              if @cache.key?(entry[:key])
                puts "Duplicate cache entry for key: #{entry[:key]}" if Aua.testing?
                next
              end
              @cache[entry[:key]] = entry[:value]
            rescue JSON::ParserError => e
              puts "Failed to parse cache entry: #{e.message}"
            end
          end
        end

        def dump(file_path)
          return unless @cache

          FileUtils.mkdir_p(File.dirname(file_path))
          File.open(file_path, "w") do |file|
            @cache.each do |key, val|
              entry = { key:, value: val }
              file.puts(entry.to_json)
            end
          end
          puts "Cache dumped to #{file_path}" if Aua.testing?
        rescue StandardError => e
          puts "Failed to dump cache: #{e.message}"
        end

        def miss(&blk) = @cache_miss_lambda = blk

        def append_to_cache_file(key, val, file_path)
          FileUtils.mkdir_p(File.dirname(file_path))
          File.open(file_path, "a") do |file|
            entry = { key:, value: val }
            puts "Appending to cache file: #{file_path} [#{key} => #{val}]" if Aua.testing?
            file.puts(entry.to_json)
          end
          puts "Appended to cache file at #{file_path} [#{key} => #{val}]" if Aua.testing?
          val
        rescue StandardError => e
          puts "Failed to append to cache file: #{e.message}"
        end

        def self.instance
          file_path = File.expand_path(
            # current working directory + "/.aua/cache.json"
            File.join(Dir.pwd, ".aua", "cache.json")
          )
          @instance ||= new.tap do |cache|
            cache.hydrate(file_path)

            # Aua.configuration.cache_file_path)

            cache.miss do |key, val|
              puts "Cache miss for key: #{key}" if Aua.testing?
              cache.append_to_cache_file(key, val, file_path)
              val
            end
          end
        end
      end

      # Represents a response from the LLM provider.
      #
      # @attr_reader model [String] The model used for the response.
      # @attr_reader prompt [String] The prompt that generated the response.
      # @attr_reader message [String] The actual response text.
      # @attr_reader requested_at [Time] The time when the request was made.
      # @attr_reader duration [Float] The time taken to generate the response.
      # @attr_reader tokens_used [Integer] The number of tokens used in the response.
      class Response
        using Rainbow

        attr_reader :model, :prompt, :message, :duration, :tokens_used

        # Initializes a new Response object.
        #
        # @param model [String] The model used for the response.
        # @param prompt [String] The prompt that generated the response.
        # @param response [String] The actual response text.
        # @param created_at [Time] The time when the response was created.
        def initialize(
          model:, prompt:, message:, requested_at:, responded_at: Time.now, tokens_used: nil, parameters: {}
        )
          @model = model
          @prompt = prompt
          @requested_at = requested_at
          @responded_at = responded_at
          @message = message.strip
          @parameters = parameters

          puts "Response created at: #{@requested_at}" if Aua.testing?
          puts "Response responded at: #{@responded_at}" if Aua.testing?
        end

        def requested_at
          return @requested_at if @requested_at.is_a?(Time)

          @requested_at.is_a?(String) ? Time.parse(@requested_at) : Time.now
        end

        def responded_at
          return @responded_at if @responded_at.is_a?(Time)

          @responded_at.is_a?(String) ? Time.parse(@responded_at) : Time.now
        end

        def duration = responded_at - requested_at

        def to_s
          outgoing = ">>> #{@prompt}".cyan
          incoming = "<<< #{@message}[..80]".blue
          timing = "(#{duration.round(2)} seconds)".black
          info = { model: @model, parameters: @parameters, tokens_used: @tokens_used || 0,
                   requested_at: requested_at.strftime("%Y-%m-%d %H:%M:%S") }
          <<~RESPONSE
            #{outgoing}
            #{incoming} #{timing}
            #{info.except(:parameters).map { |k, v| "#{k.to_s.upcase.magenta} #{v.to_s.black}" }.join(" | ")}
          RESPONSE
        end
      end

      def initialize(base_uri: Aua.configuration.base_uri)
        @base_uri = base_uri
      end

      def generation_parameters
        {
          temperature: 0.7,
          max_tokens: 1024,
          top_p: 0.9,
          frequency_penalty: 0.0,
          presence_penalty: 0.0
        }
      end

      def request(
        prompt:,
        model: Aua.configuration.model,
        generation: generation_parameters
      )
        t0 = Time.now
        rsp = db.with_cache(prompt, model:, generation:) do
          uri = URI(@base_uri + "/chat/completions")
          response = post(uri, request_body(prompt, model:, generation:).to_json)
          t1 = Time.now
          raise Error, "#{response.code} - #{response.message}" unless response.is_a?(Net::HTTPSuccess)

          # parse(response, model:, prompt:, requested_at: t0, responded_at: t1, parameters: generation)
          # response
          body = response.body
          json = JSON.parse(body)

          tokens_used = json.dig("usage", "total_tokens") || 0
          message = json.dig("choices", 0, "message", "content") || "No response content"

          # { message:, tokens_used: }
          meta = {
            message:, tokens_used:, model:, prompt:, requested_at: t0, responded_at: Time.now, parameters: generation
          }
          meta
        end
        # message = rsp[:message]
        # tokens_used = rsp[:tokens_used]

        respond_with(**rsp)
      end

      private

      def db = Cache.instance

      def request_body(prompt, model:, generation:)
        {
          messages: [{ role: "user", content: prompt }],
          model:,
          **generation
        }
      end

      def post(uri, body)
        request = Net::HTTP::Post.new(uri)
        request.content_type = "application/json"
        request.body = body
        Net::HTTP.start(uri.hostname, uri.port, read_timeout: 10) do |http|
          http.request(request)
        end
      end

      def respond_with(message: "Hello!", tokens_used: -1, **meta)
        # body = JSON.parse(response.body)
        # puts JSON.pretty_generate(body)
        # message = body.dig("choices", 0, "message", "content") || "No response content"
        # tokens_used = body.dig("usage", "total_tokens") || 0
        puts "Response: #{message}" if Aua.testing?
        puts "Tokens used: #{tokens_used}" if Aua.testing?
        puts "Meta: #{meta}" if Aua.testing?
        Response.new(
          message:,
          tokens_used:,
          **meta
        )
      end
    end

    class Chat
      using Rainbow

      def initialize
        @provider = Provider.new
      end

      def ask(prompt)
        resp = @provider.request(prompt:)
        puts resp.inspect if Aua.testing?
        timing = "(#{resp.duration.round(2)} seconds)"
        puts resp

        resp.message
      end
    end

    def self.chat = @chat ||= Aua::LLM::Chat.new
  end
end
