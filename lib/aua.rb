# frozen_string_literal: true

require "aua/version"
require_relative "aua/text"
require_relative "aua/lex"
require_relative "aua/parse"

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

  # The base object for all Aua values.
  class Obj
    def klass = Klass.klass
    def inspect = "<#{self.class.name} #{introspect}>"
    def introspect = ""
    def pretty = introspect
  end

  # The class object for Aua types.
  class Klass < Obj
    def initialize(name, parent = nil)
      super()
      @name = name
      @parent = parent
    end

    def klass = send :itself
    def self.klass = Klass.new("Klass", klass)
    def self.obj = Klass.new("Obj", klass)
    def introspect = @name
  end

  # The 'nothing' value in Aua.
  class Nihil < Obj
    def klass
      Klass.obj # : Klass
    end

    def name = "nothing"
    def value = nil
  end

  # Integer value in Aua.
  class Int < Obj
    def initialize(value)
      super()
      @value = value
    end

    def klass = Klass.new("Int", Klass.obj)
    def name = "int"
    def introspect = @value.inspect
    attr_reader :value
  end

  # Floating-point value in Aua.
  class Float < Obj
    def initialize(value)
      super()
      @value = value
    end

    def klass = Klass.new("Float", Klass.obj)
    def name = "float"
    def introspect = @value.inspect
    attr_reader :value
  end

  # Boolean value in Aua.
  class Bool < Obj
    def initialize(value)
      super()
      @value = value
    end

    def klass = Klass.new("Bool", Klass.obj)
    def name = "bool"
    def introspect = @value.inspect ? "true" : "false"
    attr_reader :value
  end

  # String value in Aua.
  class Str < Obj
    def initialize(value)
      super()
      @value = value
    end

    def klass = Klass.new("Str", Klass.obj)
    def name = "str"
    def introspect = @value.inspect
    attr_reader :value
  end

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

  RECALL = lambda do |item|
    Semantics.inst(:let, "_", item)
  end

  LOCAL_VARIABLE_GET = lambda do |name|
    Semantics.inst(:id, name)
  end

  SEND = lambda do |receiver, method, *args|
    Semantics.inst(:send, receiver, method, *args)
  end

  # The virtual machine for executing Aua ASTs.
  class VM
    # The translator class that converts Aua AST nodes into VM instructions.
    class Translator
      def initialize(virtual_machine)
        @vm = virtual_machine
      end

      def environment = @vm.instance_variable_get(:@env)

      def translate(ast)
        case ast.type
        when :nihil, :int, :float, :bool, :str then reify_primary(ast)
        when :if then translate_if(ast)
        when :negate then translate_negation(ast)
        when :id then [LOCAL_VARIABLE_GET[ast.value]]
        when :assign then translate_assignment(ast)
        when :binop then translate_binop(ast)
        else
          raise Error, "Unknown AST node type: \\#{ast.type}"
        end
      end

      def reify_primary(node)
        case node.type
        when :int then Int.new(node.value)
        when :float then Float.new(node.value)
        when :bool then Bool.new(node.value)
        when :str then Str.new(node.value)
        else
          warn "Unknown primary node type: #{node.type.inspect}"
          Nihil.new
        end
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
        op, left_node, right_node = node.value
        left = translate(left_node)
        right = translate(right_node)
        Binop.binary_operation(op, left, right) || SEND[left, op, right]
      end

      # Support translating binary operations.
      module Binop
        class << self
          def binary_operation(operator, left, right)
            case operator
            when :plus  then Binop.binop_plus(left, right)
            when :minus then Binop.binop_minus(left, right)
            when :star  then Binop.binop_star(left, right)
            when :slash then Binop.binop_slash(left, right)
            when :pow   then Binop.binop_pow(left, right)
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
            raise Error, "Unsupported operand types for #{operator}: #{left.class} and #{right.class}"
          end

          def binop_minus(left, right)
            if left.is_a?(Int) && right.is_a?(Int)
              Int.new(left.value - right.value)
            elsif left.is_a?(Float) && right.is_a?(Float)
              Float.new(left.value - right.value)
            else
              raise Error, "Unsupported operand types for -: #{left.class} and #{right.class}"
            end
          end

          def binop_star(left, right)
            if left.is_a?(Int) && right.is_a?(Int)
              Int.new(left.value * right.value)
            elsif left.is_a?(Float) && right.is_a?(Float)
              Float.new(left.value * right.value)
            else
              raise Error, "Unsupported operand types for *: #{left.class} and #{right.class}"
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
            lhs = left # : Float
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
              raise Error, "Unsupported operand types for **: #{left.class} and #{right.class}"
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

    private

    def reduce(ast) = @tx.translate(ast)

    def evaluate(ast)
      ret = Nihil.new
      stmts = reduce(ast)
      stmts = [stmts] unless stmts.is_a? Array
      stmts.each do |stmt|
        ret = stmt.is_a?(Obj) ? stmt : evaluate_one(stmt)
      end
      evaluate_one RECALL[ret]
      ret
    end

    # Evaluates a single statement in the VM.
    def evaluate_one(stmt)
      return stmt if stmt.is_a? Obj

      case stmt.type
      when :id then eval_id(stmt.value)
      when :let then eval_let(stmt.value[0], evaluate_one(stmt.value[1]))
      when :if
        cond, true_branch, false_branch = stmt.value
        eval_if(cond, true_branch, false_branch)
      else
        raise Error, "Unknown statement type: #{stmt.type}"
      end
    end

    def eval_id(identifier)
      raise Error, "Undefined variable: #{identifier}" unless @env.key?(identifier)

      @env[identifier]
    end

    def eval_let(name, value)
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
    def initialize(env = {})
      @env = env
    end

    def lex(code) = Lex.new(code).enum_for(:tokenize)
    def parse(tokens) = Parse.new(tokens).tree
    def vm = VM.new @env

    # Runs the Aua interpreter pipeline: lexing, parsing, and evaluation.
    # Something like the following:
    #
    #   code = "let x = 42"
    #   tokens = lex code
    #   ast = parse tokens
    #   vm.evaluate ast
    #
    # @param code [String] The source code to interpret.
    def run(code)
      pipeline = [method(:lex), method(:parse), vm.method(:evaluate)]
      pipeline.reduce(code) do |input, step|
        # $stdout.puts "#{step.name}: #{input.inspect}..."
        out = step.call(input)
        $stdout.puts "#{step.name}: #{input.inspect} -> #{out.inspect}" if $DEBUG
        out
      rescue Aua::Error => e
        warn "Error during processing: #{e.message}"
        # would be nice to trace errors here somehow but we'd have to thread the position through the pipeline!
        raise e
      end
    end
  end

  # The main entry point for the Aua interpreter.
  #
  # @example
  #   Aua.run("some code")
  def self.run(code)
    @current_interpreter ||= Interpreter.new

    @current_interpreter.run(code)
  end
end
