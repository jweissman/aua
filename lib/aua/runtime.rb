require "aua/runtime/statement"
require "aua/runtime/semantics"
require "aua/runtime/vm"
require "aua/runtime/type_registry"
require "aua/runtime/json_schema"
require "aua/runtime/record_type"
require "aua/runtime/type_classes"

module Aua
  module Runtime
    include Semantics

    # The main interpreter class that combines lexing, parsing, and evaluation.
    #
    # @example
    # ```
    #   interpreter = Aua::Interpreter.new
    #   result = interpreter.run("some code")
    # ```
    #
    # @see Aua::Lex for lexing functionality
    # @see Aua::Parse for parsing functionality
    # @see Aua::Vm for virtual machine execution
    class Interpreter
      attr_reader :env

      def initialize(env = {})
        Aua.logger.debug "Initializing Aua interpreter with env: #{env.inspect}"
        @env = env.merge(self.class.prelude_env)
        # @ctx = ctx
      end

      def lex(_ctx, code) = Lex.new(code).enum_for(:tokenize)
      def parse(ctx, tokens) = Parse.new(tokens, ctx).tree
      def vm = @vm ||= Aua.vm(@env) || VM.new(@env)

      def self.prelude_env
        {
          "Str" => Aua::Str.klass,
          "Bool" => Aua::Bool.klass,
          "Nihil" => Aua::Nihil.klass,
          "Int" => Aua::Int.klass,
          "List" => Aua::List.klass
        }
      end

      # Runs the Aua interpreter pipeline: lexing, parsing, and evaluation.
      # Something like the following:
      #
      #   code = "let x = 42"
      #   tokens = lex code
      #   ast = parse tokens
      #   vm.evaluate ast
      #
      # @param code [String] The source code to interpret.
      def run(ctx, code)
        # Aua.logger.warn "Running Aua interpreter with code: #{code.inspect}"
        pipeline = [method(:lex), method(:parse), vm.method(:evaluate)]
        pipeline.reduce(code) do |input, step|
          out = step.call(ctx, input)
          Aua.logger.debug "#{step.name}: #{input.inspect} -> #{out.inspect}"
          out
        rescue Aua::Error => e
          warn "Error during processing: #{e.message}"
          # would be nice to trace errors here somehow but we'd have to thread the position through the pipeline!
          raise e
        end
      end
    end

    class Context
      def initialize(source = "")
        @source = source
      end

      def source_document = @source_document ||= Text::Document.new(@source)
    end

    # Global interpreter settings.
    class Configuration < Data.define(:testing, :model, :base_uri, :temperature, :top_p, :max_tokens)
      # Default values for the configuration
      def self.default(
        testing: ENV.fetch("AURA_DEBUG", "false") == "true",
        model: "qwen-2.5-1.5b-chat",
        base_uri: "http://10.0.0.158:1234/v1",
        temperature: 0.7,
        max_tokens: 1024
      )
        new(
          testing:,
          model:,
          base_uri:,
          temperature:,
          top_p: 0.9,
          max_tokens:
        )
      end
    end
  end
end
