# frozen_string_literal: true

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
    #   Aua.logger.info response.message
    class Provider
      class Error < StandardError; end

      # The Cache class is responsible for caching responses from the LLM provider.
      # It uses a simple in-memory hash to store cached responses and provides methods
      # to fetch, hydrate, and dump the cache to a file.
      #
      # @example
      #   cache = Aua::LLM::Provider::Cache.instance
      #   cache.with_cache("some_key") { "some_value" }
      #
      # @see Aua::LLM::Provider::Response
      class Cache
        def initialize(
          file_path: self.class.file_path
        )
          @cache = {} # : Hash[String, completion_trace]
          @cache_miss_lambda = nil

          unless File.exist?(file_path)
            warn "Cache file does not exist, creating: #{file_path}"
            FileUtils.mkdir_p(File.dirname(file_path))
          end

          hydrate(file_path)
          miss do |key, val|
            warn "Cache miss for key: #{key}"
            append_to_cache_file(key, val, file_path)
            val
          end
        end

        def self.simple_key(*args)
          key_content = args.join(":")
          Digest::SHA256.hexdigest(
            key_content + Aua.configuration.model + Aua.configuration.base_uri
          )
        end

        def fetch(key, &)
          @cache ||= {} # : Hash[String, completion_trace]
          unless @cache.key?(key)
            val = fetch!(key, &)
            if @cache_miss_lambda
              @cache_miss_lambda.call(key, val)
            else
              warn "No cache miss handler defined!"
            end
          end
          @cache[key]
        end

        def fetch!(key, &block)
          val = block.call
          @cache[key] = val
          val
        end

        def with_cache(the_key, &)
          @cache ||= {} # : Hash[String, completion_trace]
          missed = !@cache.key?(the_key)
          val = fetch(the_key, &)
          @cache_miss_lambda.call(the_key, val) if missed && @cache_miss_lambda
          val
        end

        def hydrate(file_path)
          return unless File.exist?(file_path)

          @cache ||= {} # : Hash[String, completion_trace]

          File.open(file_path, "r") do |file|
            file.each_line do |line|
              next if line.start_with?("#") || line.strip.empty?

              hydrate_line(line.strip)
            end
          end
        end

        def hydrate_line(line)
          entry = JSON.parse(line, symbolize_names: true)
          if @cache.key?(entry[:key])
            Aua.logger.info "Cache already contains key: #{entry[:key]}"
            return
          end
          @cache[entry[:key]] = entry[:value]
        rescue JSON::ParserError => e
          warn "Failed to parse cache entry: #{e.message}"
        end

        def dump(file_path)
          FileUtils.mkdir_p(File.dirname(file_path))
          File.open(file_path, "w") do |_file|
            @cache.each do |key, val|
              entry = { key:, value: val }
              Aua.logger.info(entry.to_json)
            end
          end
        end

        def miss(&blk) = @cache_miss_lambda = blk

        def append_to_cache_file(key, val, file_path)
          FileUtils.mkdir_p(File.dirname(file_path))
          File.open(file_path, "a") do |_file|
            entry = { key:, value: val }
            Aua.logger.info "Appending to cache file: #{file_path} [#{key} => #{val}]"
            Aua.logger.info(entry.to_json)
          end
          Aua.logger.info "Appended to cache file at #{file_path} [#{key} => #{val}]"
          val
        rescue StandardError => e
          Aua.logger.info "Failed to append to cache file: #{e.message}"
        end

        def self.file_path
          env = Aua.testing ? "test" : "dev"
          file_name = "responses.json"
          File.expand_path(File.join(Dir.pwd, ".aua", env, file_name))
        end

        def self.instance
          @instance ||= new
          # .tap do |cache|

          # end
          # end
        end
      end

      # Represents a response from the LLM provider.
      #
      # @attr_reader prompt [String] The prompt that generated the response.
      # @attr_reader message [String] The actual response text.
      class Response
        using Rainbow

        # Represents metadata about the response, including model, timing, and token usage.
        # @attr_reader model [String] The model used for the response.
        # @attr_reader requested_at [Time] The time when the request was made.
        # @attr_reader duration [Float] The time taken to generate the response.
        # @attr_reader tokens_used [Integer] The number of tokens used in the response.
        class Metadata
          attr_reader :model, :tokens_used, :parameters

          def initialize(model:, requested_at:, responded_at:, tokens_used: nil, parameters: {})
            @model = model
            @requested_at = requested_at.is_a?(::Time) ? requested_at : ::Time.parse(requested_at.to_s)
            @responded_at = responded_at.is_a?(::Time) ? responded_at : ::Time.parse(responded_at.to_s)
            @tokens_used = tokens_used || 0
            @parameters = parameters
          end

          def self.coerce_timestamp(timestamp)
            return timestamp if timestamp.is_a?(::Time)

            if timestamp.is_a?(String)
              ::Time.parse(timestamp)
            else
              ::Time.now
            end
          end

          def requested_at = Metadata.coerce_timestamp @requested_at
          def responded_at = Metadata.coerce_timestamp @responded_at
          def duration = responded_at - requested_at

          def timing
            "(#{duration.round(2)} seconds)".black
          end

          def to_s
            details = { model:, parameters:, requested_at: requested_at.strftime("%Y-%m-%d %H:%M:%S") }
            details.except(:parameters).map { |k, v| "#{k.to_s.upcase.magenta} #{v.to_s.black}" }.join(" | ")
          end
        end

        attr_reader :prompt, :message, :metadata # duration, :tokens_used

        # Initializes a new Response object.
        #
        # @param model [String] The model used for the response.
        # @param prompt [String] The prompt that generated the response.
        # @param response [String] The actual response text.
        # @param created_at [Time] The time when the response was created.
        def initialize(prompt:, message:, metadata: nil)
          @prompt = prompt
          @message = message.strip
          @metadata = metadata
        end

        def to_s = message

        def inspect
          outgoing = ">>> #{@prompt}".cyan
          incoming = "<<< #{@message}[..80]".blue

          <<~RESPONSE
            #{outgoing}
            #{incoming} #{@metadata.timing}
            #{@metadata}
          RESPONSE
        end
      end

      # Attempts to generate a response from the LLM provider based on a given prompt.
      class Completion
        attr_reader :prompt, :model, :generation

        def initialize(
          prompt:,
          model: Aua.configuration.model,
          generation: {},
          base_uri: Aua.configuration.base_uri
        )
          @prompt = prompt
          @model = model
          @generation = generation
          @base_uri = base_uri
        end

        def generate
          key = Cache.simple_key([prompt, { model:, generation: }])
          db.with_cache(key) { call }
        end

        protected

        def call
          request(prompt:, model:, generation:)
        rescue Error => e
          Aua.logger.info "Error during LLM request: #{e.message}"
          raise e
        rescue StandardError => e
          Aua.logger.info "Unexpected error during LLM request: #{e.message}"
          raise Error, "Failed to get response from LLM provider: #{e.message}"
        end

        private

        def request(prompt:, model: Aua.configuration.model, generation: nil)
          Aua.logger.info "Requesting LLM completion for prompt: '#{prompt}' with model: '#{model}'"
          uri = URI("#{@base_uri}/chat/completions")
          t0 = ::Time.now # ::Time
          response = post(uri, request_body(prompt, model:, generation:).to_json)
          t1 = ::Time.now # ::Time
          raise Error, "#{response.code} - #{response.message}" unless response.is_a?(Net::HTTPSuccess)

          read_response(response.body, prompt:,
                                       meta: { model:, parameters: generation, requested_at: t0, responded_at: t1 })
        end

        def read_response(body, prompt:, meta: {})
          model, parameters, requested_at, responded_at = meta.values_at(
            :model, :parameters, :requested_at, :responded_at
          )
          json = JSON.parse(body)
          tokens_used = json.dig("usage", "total_tokens") || 0
          message = json.dig("choices", 0, "message", "content") || "No response content"
          { message:, tokens_used:, model:, prompt:, requested_at:, responded_at:, parameters: }
        end

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
      end

      def generation_parameters
        fetch_meta = ->(key) { Aua.configuration.send(key) }
        {
          temperature: fetch_meta[:temperature],
          max_tokens: fetch_meta[:max_tokens],
          top_p: fetch_meta[:top_p],
          frequency_penalty: 0.0,
          presence_penalty: 0.0
        }
      end

      def chat_completion(
        prompt:,
        model: Aua.configuration.model,
        generation: generation_parameters
      )
        completion = Completion.new(prompt:, model:, generation:)
        rsp = completion.generate
        metadata = Response::Metadata.new(
          model: rsp[:model],
          requested_at: rsp[:requested_at],
          responded_at: rsp[:responded_at],
          tokens_used: rsp[:tokens_used] || 0,
          parameters: rsp[:parameters]
        )
        Response.new(prompt:, message: rsp[:message], metadata:)
      end
    end

    # Entry point for interacting with the LLM provider.
    class Chat
      using Rainbow

      def initialize
        @provider = Provider.new
      end

      def ask(prompt)
        resp = @provider.chat_completion(prompt:)
        Aua.logger.info resp.inspect
        Aua.logger.info resp

        resp.message
      end
    end

    def self.chat = @chat ||= Aua::LLM::Chat.new
  end
end
