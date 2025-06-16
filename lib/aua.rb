# frozen_string_literal: true

# require "json"
# require "net/http"
# require "logger"
require "ostruct"
require "rainbow"
require "rainbow/refinement"

require "aua/version"
require "aua/logger"
require "aua/error"
require "aua/text"
require "aua/lex"
require "aua/parse"
require "aua/obj"
require "aua/llm/provider"
require "aua/runtime"

# The main Aua interpreter module.
#
# Aua is a programming language and interpreter written in Ruby.
# This module serves as the entry point for using the Aua interpreter,
# providing functionality for lexing, parsing, and executing Aua code.
#
# @example
#   Aua.run("let x = 42")
module Aua
  class << self
    # The main entry point for the Aua interpreter.
    #
    # @example
    #   Aua.run("some code")
    def run(code)
      ctx = Runtime::Context.new(code)

      interpreter.run(ctx, code)
    end

    def vm(env = {})
      @vm ||= Runtime::VM.new
      unless env.empty?
        @vm.instance_variable_set(:@env, env.merge(@vm.instance_variable_get(:@env) || {
                                                     #  hi: Aua::Str.new("Hello, world!")
                                                   }))
      end
      @vm
    end

    def configuration
      @configuration ||= Runtime::Configuration.default
    end

    def configure
      yield(configuration) if block_given?
    end

    def interpreter = @interpreter ||= Runtime::Interpreter.new

    def testing = @testing ||= !!configuration.testing

    attr_writer :testing

    # Returns true if the interpreter is in testing mode.
    #
    # @return [Boolean] true if testing mode is enabled, false otherwise.
    #
    # @example
    #   Aua.testing? # => false
    #   Aua.testing = true
    #   Aua.testing? # => true
    def testing? = testing || false
  end
end
