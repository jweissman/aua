require "net/http"
require "json"

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
        attr_reader :model, :prompt, :message, :requested_at, :duration, :tokens_used

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
        end

        def duration = @responded_at - @requested_at

        def to_s
          outgoing = ">>> #{@prompt}".cyan
          incoming = "<<< #{@message}[..80]".blue
          timing = "(#{duration.round(2)} seconds)".black
          info = { model: @model, parameters: @parameters, tokens_used: @tokens_used || 0,
                   requested_at: @requested_at.strftime("%Y-%m-%d %H:%M:%S") }
          <<~RESPONSE
            #{outgoing}
            #{incoming} #{timing}
            #{info.except(:parameters).map { |k, v| "#{k.to_s.upcase.magenta} #{v.to_s.black}" }.join(" | ")}
          RESPONSE
        end
      end

      def initialize(base_uri: "http://10.0.0.158:1234/v1")
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
        uri = URI(@base_uri + "/chat/completions")
        response = post(uri, request_body(prompt, model:, generation:).to_json)
        t1 = Time.now
        raise "Remote Generation Error: #{response.code} - #{response.message}" unless response.is_a?(Net::HTTPSuccess)

        parse(response, model:, prompt:, requested_at: t0, responded_at: t1, parameters: generation)
      end

      private

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

      def parse(response, **meta)
        body = JSON.parse(response.body)
        # puts JSON.pretty_generate(body)
        message = body.dig("choices", 0, "message", "content") || "No response content"
        tokens_used = body.dig("usage", "total_tokens") || 0
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
        timing = "(#{resp.duration.round(2)} seconds)"
        puts resp

        resp.message
      end
    end

    def self.chat = @chat ||= Aua::LLM::Chat.new
  end
end
