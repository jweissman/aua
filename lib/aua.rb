# frozen_string_literal: true

# require "json"
# require "net/http"
# require "logger"
require "ostruct"
require "rainbow"
require "rainbow/refinement"

require "aua/version"
require "aua/logger"
require "aua/text"
require "aua/lex"
require "aua/parse"
require "aua/obj"
require "aua/llm/provider"

# The main Aua interpreter module.
#
# Aua is a programming language and interpreter written in Ruby.
# This module serves as the entry point for using the Aua interpreter,
# providing functionality for lexing, parsing, and executing Aua code.
#
# @example
#   Aua.run("let x = 42")
module Aua
  class Error < StandardError; end

  # Represents a statement in Aua, which can be an assignment, expression, or control flow.
  class Statement < Data.define(:type, :value)
    def inspect
      "#{type.upcase} #{value.inspect}"
    end
  end

  # Semantic helpers for statements and let bindings.
  module Semantics
    MEMO = "_"
    def self.inst(type, *args)
      Statement.new(type:, value: args)
    end
  end

  include Semantics

  # The virtual machine for executing Aua ASTs.
  class VM
    module Commands
      include Semantics
      RECALL = lambda do |item|
        Semantics.inst(:let, Semantics::MEMO, item)
      end

      LOCAL_VARIABLE_GET = lambda do |name|
        Semantics.inst(:id, name)
      end

      SEND = lambda do |receiver, method, *args|
        Semantics.inst(:send, receiver, method, *args)
      end

      CONCATENATE = lambda do |parts|
        # Concatenate an array of parts into a single string.
        # This is used for structured strings.
        Semantics.inst(:cat, *parts)
      end

      GEN = lambda do |prompt|
        Semantics.inst(:gen, prompt)
      end
    end

    # The translator class that converts Aua AST nodes into VM instructions.
    class Translator
      include Commands

      def initialize(virtual_machine)
        @vm = virtual_machine
      end

      def environment = @vm.instance_variable_get(:@env)

      def translate(ast)
        case ast.type
        when :nihil, :int, :float, :bool, :simple_str, :str then reify_primary(ast)
        when :if, :negate, :id, :assign, :binop then translate_basic(ast)
        when :gen_lit then translate_gen_lit(ast)
        when :call then translate_call(ast)
        when :seq then translate_sequence(ast)
        when :structured_str, :structured_gen_lit
          # Join all parts, recursively translating expressions
          Aua.logger.info "Translating structured string: #{ast.inspect}"

          parts = ast.value.map do |part|
            Aua.logger.info "Translating part: #{part.inspect}"
            if part.is_a?(AST::Node)
              val = translate(part)
              val = val.first if val.is_a?(Array) && val.size == 1
              val.is_a?(Str) ? val.value : val
            else
              part.to_s
            end
          end

          Aua.logger.info "Structured string parts: #{parts.inspect}"

          if ast.type == :structured_gen_lit
            [GEN[CONCATENATE[parts]]] # Use CHAT to handle structured generative strings
          else
            [CONCATENATE[parts]] # Concatenate all parts into a single string
          end
        else
          raise Error, "Unknown AST node type: \\#{ast.type}"
        end
      end

      def translate_call(node)
        fn_name, args = node.value
        [Semantics.inst(:call, fn_name, *args.map { |a| translate(a) })]
      end

      def translate_sequence(node)
        stmts = node.value
        Aua.logger.info "Translating sequence: #{stmts.inspect}"
        raise Error, "Empty sequence" if stmts.empty?
        raise Error, "Sequence must be an array" unless stmts.is_a?(Array)
        raise Error, "Sequence must contain only AST nodes" unless stmts.all? { |s| s.is_a?(AST::Node) }

        stmts.map { |stmt| translate(stmt) }.flatten
      end

      def translate_basic(node)
        case node.type
        when :if then translate_if(node)
        when :negate then translate_negation(node)
        when :id then [LOCAL_VARIABLE_GET[node.value]]
        when :assign then translate_assignment(node)
        when :binop then translate_binop(node)
        else
          raise Error, "Unknown Basic AST node type: \\#{node.type}"
        end
      end

      def reify_primary(node)
        case node.type
        when :int then Int.new(node.value)
        when :float then Float.new(node.value)
        when :bool then Bool.new(node.value)
        when :str, :simple_str
          Aua.logger.info "Reifying string: #{node.inspect}"
          Str.new(node.value)
        else
          warn "Unknown primary node type: #{node.type.inspect}"
          Nihil.new
        end
      end

      def translate_gen_lit(node)
        value = node.value
        current_conversation = Aua::LLM.chat
        [Str.new(current_conversation.ask(value))]
      end

      def translate_if(node)
        condition, true_branch, false_branch = node.value
        [
          Semantics.inst(:if, translate(condition), translate(true_branch), translate(false_branch))
        ]
      end

      def translate_negation(node)
        operand = node.value

        negated = case operand.type
                  when :int then Int.new(-operand.value)
                  when :float then Float.new(-operand.value)
                  else
                    raise Error, "Negation only supported for Int and Float"
                  end
        [RECALL[negated]]
      end

      def translate_assignment(node)
        name, value_node = node.value
        value = translate(value_node)
        [Semantics.inst(:let, name, value)]
      end

      def translate_binop(node)
        Aua.logger.info "Translating binop: #{node.inspect}"
        op, left_node, right_node = node.value
        left = translate(left_node)
        right = translate(right_node)
        Binop.binary_operation(op, left, right) || SEND[left, op, right]
      end

      # Support translating binary operations.
      module Binop
        class << self
          include Commands
          def binary_operation(operator, left, right)
            case operator
            when :plus then Binop.binop_plus(left, right)
            when :minus then Binop.binop_minus(left, right)
            when :star then Binop.binop_star(left, right)
            when :slash then Binop.binop_slash(left, right)
            when :pow then Binop.binop_pow(left, right)
            else
              raise Error, "Unknown binary operator: #{operator}"
            end
          end

          def binop_plus(left, right)
            return int_plus(left, right) if left.is_a?(Int) && right.is_a?(Int)
            return float_plus(left, right) if left.is_a?(Float) && right.is_a?(Float)
            return str_plus(left, right) if left.is_a?(Str) && right.is_a?(Str)

            raise_binop_type_error(:+, left, right)
          end

          def int_plus(left, right)
            Int.new(left.value + right.value)
          end

          def float_plus(left, right)
            Float.new(left.value + right.value)
          end

          def str_plus(left, right)
            Str.new(left.value + right.value)
          end

          def raise_binop_type_error(operator, left, right)
            [SEND[left, operator, right]]
          end

          def binop_minus(left, right)
            if left.is_a?(Int) && right.is_a?(Int)
              Int.new(left.value - right.value)
            elsif left.is_a?(Float) && right.is_a?(Float)
              Float.new(left.value - right.value)
            else
              raise_binop_type_error(:-, left, right)
            end
          end

          def binop_star(left, right)
            if left.is_a?(Int) && right.is_a?(Int)
              Int.new(left.value * right.value)
            elsif left.is_a?(Float) && right.is_a?(Float)
              Float.new(left.value * right.value)
            else
              raise_binop_type_error(:*, left, right)
            end
          end

          def binop_slash(left, right)
            return int_slash(left, right) if left.is_a?(Int) && right.is_a?(Int)
            return float_slash(left, right) if left.is_a?(Float) && right.is_a?(Float)

            raise_binop_type_error(:/, left, right)
          end

          def int_slash(left, right)
            raise Error, "Division by zero" if right.value.zero?

            Int.new(left.value / right.value)
          end

          def float_slash(left, right)
            lhs = left  # : Float
            rhs = right # : Float
            raise Error, "Division by zero" if rhs.value == 0.0

            Float.new(lhs.value / rhs.value)
          end

          def binop_pow(left, right)
            if left.is_a?(Int) && right.is_a?(Int)
              Int.new(
                left.value**right.value # : Integer
              )
            elsif left.is_a?(Float) && right.is_a?(Float)
              Float.new(left.value**right.value)
            else
              # raise Error, "Unsupported operand types for **: #{left.class} and #{right.class}"
              raise_binop_type_error(:**, left, right)
            end
          end
        end
      end
    end

    extend Semantics

    def initialize(env = {})
      @env = env
      @tx = Translator.new(self)
    end

    def builtins
      @builtins ||= {
        inspect: lambda { |obj|
          Aua.logger.info "Inspecting object: #{obj.inspect}"
          raise Error, "inspect requires a single argument" unless obj.is_a?(Obj)

          Aua.logger.info "Object class: #{obj.class}"
          # Aua.logger.info "Object value: #{obj.value.inspect}"

          Str.new(obj.introspect)
        },
        rand: lambda { |max|
          Aua.logger.info "Generating random number... (max: #{max.inspect})"
          rng = Random.new
          max = max.is_a?(Int) ? max.value : 100 if max.is_a?(Obj)
          Aua.logger.info "Using max value: #{max}"
          Aua::Int.new(
            rng.rand(0..max)
          )
        },
        time: lambda { |_args|
          Aua.logger.info "Current time: #{Time.now}"
          Aua::Time.now
        },
        say: lambda { |arg|
          # raise Error, "say requires a single argument" unless args.size == 1

          value = arg # s.first
          raise Error, "say only accepts Str arguments, got #{value.class}" unless value.is_a?(Str)

          puts arg.value

          Aua::Nihil.new
        },
        ask: lambda { |question| # ie from stdin
          Aua.logger.info "Asking question: #{question.inspect}"
          raise Error, "ask requires a single Str argument" unless question.is_a?(Str)

          Aua.logger.info "Asking question: #{question.value}"
          response = $stdin.gets
          Aua.logger.info "Response: #{response}"
          raise Error, "No response received" if response.nil?

          Str.new(response.chomp) # .strip
        },
        chat: lambda { |question|
          Aua.logger.info "Asking question: #{question.inspect}"
          raise Error, "ask requires a single Str argument" unless question.is_a?(Str)

          current_conversation = Aua::LLM.chat
          response = current_conversation.ask(question.value)
          Aua.logger.info "Response: #{response}"
          Aua::Str.new(response)
        },
        see_url: lambda { |url|
          Aua.logger.info "Fetching URL: #{url.inspect}"
          raise Error, "see_url requires a single Str argument" unless url.is_a?(Str)

          uri = URI(url.value)
          response = Net::HTTP.get_response(uri)
          raise Error, "Failed to fetch URL: #{url.value} - #{response.message}" unless response.is_a?(Net::HTTPSuccess)

          Aua.logger.info "Response from #{url.value}: #{response.body}"
          Aua::Str.new(response.body)
        }

      }
    end

    private

    def reduce(ast) = @tx.translate(ast)

    def evaluate(_ctx, ast)
      ret = Nihil.new
      stmts = reduce(ast)
      stmts = [stmts] unless stmts.is_a? Array
      stmts.each do |stmt|
        ret = stmt.is_a?(Obj) ? stmt : evaluate_one(stmt)
      end
      evaluate_one Commands::RECALL[ret]
      ret
    end

    # Evaluates a single statement in the VM.
    def evaluate_one(stmt)
      # Unwrap arrays of length 1 until we get a Statement
      stmt = stmt.first while stmt.is_a?(Array) && stmt.size == 1
      return resolve(stmt) if stmt.is_a? Obj

      raise Error, "Unexpected array in evaluate_one: \\#{stmt.inspect}" if stmt.is_a?(Array)

      Aua.logger.info stmt.inspect

      case stmt.type
      when :id then eval_id(stmt.value)
      when :let then eval_let(stmt.value[0], evaluate_one(stmt.value[1]))
      when :gen then eval_call(:chat, [stmt.value])
      when :if
        cond, true_branch, false_branch = stmt.value
        eval_if(cond, true_branch, false_branch)
      when :call
        fn_name, *args = stmt.value
        eval_call(fn_name, args.map { |a| evaluate_one(a) })
      when :send
        receiver, method, *args = stmt.value
        receiver = evaluate_one(receiver)
        args = args.map { |a| evaluate_one(a) }

        unless receiver.is_a?(Obj) && receiver.aura_respond_to?(method)
          raise Error, "Unknown aura method '#{method}' for #{receiver.class}"
        end

        receiver.aura_send(method, *args)
      when :cat
        Aua.logger.info "Concatenating parts: #{stmt.value.inspect}"
        to_ruby_str = lambda { |maybe_str|
          case maybe_str
          when String
            maybe_str
          when Str
            maybe_str.value
          when Obj
            Aua.logger.info "Converting object to string: #{maybe_str.inspect}"
            maybe_str.aura_send(:to_s)
          else
            raise Error, "Cannot concatenate non-string object: #{maybe_str.inspect}"
          end
        }
        parts = stmt.value.map do |part|
          part.is_a?(String) ? part : to_ruby_str.call(evaluate_one(part))
        end
        # Concatenate all parts into a single string
        Str.new(parts.join) # map { |p| p.is_a?(Str) ? p.value : p.to_s }.join)
      else
        raise Error, "Unknown statement type: #{stmt.type}" if stmt.is_a?(Statement)

        raise Error, "Unknown statement: #{stmt.inspect}"
      end
    end

    def resolve(obj)
      Aua.logger.info "Resolving object: #{obj.inspect}"

      # interpolate strings, collapse complex vals, etc.
      return interpolated(obj) if obj.is_a?(Str)

      obj
    end

    def interpolated(obj)
      # Aua.logger.info "Interpolating object: #{obj.inspect}"
      return obj unless obj.is_a?(Str)

      Aua.logger.info "Interpolating string: #{obj.inspect}"
      # debugger

      Aua.vm.builtins[:inspect]

      # Str.new(obj.value.gsub(/\$\{(\w+)\}/) do |match|
      #   var_name = ::Regexp.last_match(1)
      #   Aua.logger.info "Interpolating variable: #{var_name}"
      #   value = inspects[eval_id(var_name)].value
      #   Aua.logger.info "Interpolated value: #{value.inspect}"
      #   value.is_a?(Str) ? value.value : value.to_s
      # end)
      obj
    end

    def eval_call(fn_name, args)
      fn = Aua.vm.builtins[fn_name.to_sym]
      raise Error, "Unknown builtin: #{fn_name}" unless fn

      evaluated_args = [*args].map { |a| evaluate_one(a) }
      fn.call(*evaluated_args)
    end

    def eval_id(identifier)
      identifier = identifier.first if identifier.is_a?(Array)
      Aua.logger.info "Getting variable #{identifier}"
      raise Error, "Undefined variable: #{identifier}" unless @env.key?(identifier)

      @env[identifier]
    end

    def eval_let(name, value)
      Aua.logger.info "Setting variable #{name} to #{value.inspect}"
      @env[name] = value
      value
    end

    def eval_if(condition, true_branch, false_branch)
      condition_value = evaluate_one(condition)
      if condition_value.is_a?(Bool) && condition_value.value
        evaluate_one(true_branch)
      elsif false_branch
        evaluate_one(false_branch)
      end
    end
  end

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
      Aua.logger.info "Initializing Aua interpreter with env: #{env.inspect}"
      @env = env
    end

    def lex(_ctx, code) = Lex.new(code).enum_for(:tokenize)
    def parse(_ctx, tokens) = Parse.new(tokens).tree
    def vm = @vm ||= Aua.vm(@env) || VM.new(@env)

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
      Aua.logger.warn "Running Aua interpreter with code: #{code.inspect}"
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
    def initialize(source)
      @source = source
    end

    def source_document = @source
  end

  # The main entry point for the Aua interpreter.
  #
  # @example
  #   Aua.run("some code")
  def self.run(code)
    # @current_interpreter ||= Interpreter.new
    ctx = Context.new(code) # { source_document: Text::Document.new(code) }

    interpreter.run(ctx, code)
  end

  def self.interpreter = @interpreter ||= Interpreter.new

  def self.testing = @testing ||= !!configuration.testing
  def self.testing? = testing || false

  def self.testing=(value)
    @testing = value
  end

  # Global interpreter settings.
  class Configuration < Data.define(:testing, :model, :base_uri, :temperature, :top_p, :max_tokens)
    # Default values for the configuration
    def self.default(
      testing: ENV.fetch("AURA_DEBUG", "false") == "true",
      model: "qwen-2.5-1.5b-chat",
      base_uri: "http://10.0.0.158:1234/v1",
      temperature: 0.7,
      # top_p: 0.9,
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

  def self.configuration
    @configuration ||= Configuration.default
  end

  def self.configure
    yield(configuration) if block_given?
  end

  def self.vm(env = {})
    @vm ||= VM.new

    # maybe need to meld envs ???
    @vm.instance_variable_set(:@env, env.merge(@vm.instance_variable_get(:@env) || {})) unless env.empty?

    @vm
  end
end
