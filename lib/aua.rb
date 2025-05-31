# frozen_string_literal: true

require "aua/version"
require_relative "aua/text"
require_relative "aua/lex"

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

  # The AST (Abstract Syntax Tree) node definitions for Aua.
  module AST
    Node = Data.define(:type, :value)
  end

  # Grammar helpers for constructing AST nodes.
  module Grammar
    def s(type, *values)
      normalized_values = if values.empty?
                            nil
                          else
                            values.length == 1 ? values.first : values
                          end
      AST::Node.new(type:, value: normalized_values)
    end

    # A class for parsing primitive values in Aua.
    class Primitives
      include Grammar

      def initialize(parse)
        @parse = parse
      end

      def parse_id
        identifier = @parse.current_token.value
        @parse.consume(:id)
        s(:id, identifier)
      end

      def parse_number
        number = @parse.current_token.value
        @parse.consume(:number)
        s(:int, number)
      end

      def parse_float
        float = @parse.current_token.value
        @parse.consume(:float)
        s(:float, float)
      end

      def parse_bool
        bool = @parse.current_token.value
        @parse.consume(:bool)
        s(:bool, bool)
      end

      def parse_str
        str = @parse.current_token.value
        @parse.consume(:str)
        s(:str, str)
      end

      def parse_nihil
        @parse.consume(:nihil)
        s(:nihil, nil)
      end

      def parse_parens
        @parse.consume(:lparen)
        expr = @parse.parse_expression
        @parse.consume(:rparen)
        expr
      end

      # Parses a unary minus expression.
      def parse_negation
        @parse.consume(:minus)
        raise Error, "Unexpected end of input after unary minus" if @parse.current_token.type == :eos

        unless %i[number float bool str id minus].include?(@parse.current_token.type)
          raise Error, "Unary minus must be followed by a literal or identifier, got #{@parse.current_token.type}"
        end

        operand = @parse.parse_primary
        s(:negate, operand)
      end
    end
  end

  extend Grammar
  NOTHING = s(:nihil)

  # A parser for the Aua language that builds an abstract syntax tree (AST).
  # Consumes tokens and produces an AST.
  class Parse
    PRIMARY_MAP = {
      lparen: :parse_parens,
      minus: :parse_negation,
      id: :parse_id,
      number: :parse_number,
      float: :parse_float,
      bool: :parse_bool,
      str: :parse_str,
      nihil: :parse_nihil
    }.freeze

    attr_reader :current_token

    include Grammar
    include Syntax

    def initialize(tokens)
      @tokens = tokens # .is_a?(Enumerator) ? tokens : tokens.each
      @buffer = []

      puts "Initializing parser with tokens: #{tokens.inspect}"

      advance # fill @current_token
    end

    def advance
      @current_token = @buffer.shift || next_token
      # rescue StandardError
      #   AST::Node.new(type: :eos, value: nil)
      # end
    end

    def consume(expected_type)
      unless @current_token.type == expected_type
        raise Error, "Expected token type #{expected_type}, but got #{@current_token&.type || "EOF"}"
      end

      advance
    end

    def next_token
      @tokens.next
    rescue StopIteration
      AST::Node.new(type: :eos, value: nil) # End of stream token
    end

    def peek_token
      @buffer[0] ||= begin
        @tokens.next
      rescue StandardError
        AST::Node.new(type: :eos, value: nil)
      end
    end

    def tree
      # raise(Error, "Empty input") if @tokens.empty?

      ast = parse
      raise(Error, "Unexpected tokens after parsing: \\#{@current_token.inspect}") if unexpected_tokens?

      ast
    end

    def unexpected_tokens?
      @length != @current_token_index && @current_token.type != :eos
    end

    def parse = parse_expression

    # Operator precedence (higher number = higher precedence)
    BINARY_PRECEDENCE = {
      plus: 1, minus: 1,
      star: 2, slash: 2
    }.freeze

    # Parses an expression with binary operators, respecting precedence and associativity.
    def parse_expression(min_prec = 0)
      # Assignment: id = expr
      if @current_token.type == :id && peek_token&.type == :equals
        id = @current_token
        consume(:id)
        name = id.value
        consume(:equals)
        value = parse_expression
        return s(:assign, name, value)
        # return s(:id, name) # just an identifier...?
      end
      left = parse_primary
      while binary_op?(@current_token.type) && BINARY_PRECEDENCE[@current_token.type] >= min_prec
        op_token = @current_token
        op = op_token.type
        prec = BINARY_PRECEDENCE[op]
        consume(op)
        # Right-associative: parse_expression(prec), left-associative: parse_expression(prec+1)
        right = parse_expression(prec + 1)
        left = s(:binop, op, left, right)
      end

      left
    end

    def binary_op?(type) = BINARY_PRECEDENCE.key?(type)

    def parse_primary
      if @current_token.nil?
        puts "!!! No current token to parse"
        raise Aua::Error, "No current token to parse"
      end

      if @current_token.type == :eos
        puts "!!! Unexpected end of input"
        raise Aua::Error, "Unexpected end of input while parsing primary expression"
      end

      primitives = Primitives.new(self)
      return primitives.send PRIMARY_MAP[@current_token.type] if PRIMARY_MAP.key?(@current_token.type)

      raise Error, "Unexpected token type: #{@current_token.type}"
    end

    def unexpected_token
      raise Error, "Unexpected token in primary expression: #{@current_token.type}"
    end

    def self.ast(...) = new(...).tree
  end

  # The base object for all Aua values.
  class Obj
    def klass = Klass.klass
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
    attr_reader :value
  end

  Statement = Data.define(:type, :value)

  # Semantic helpers for statements and let bindings.
  module Semantics
    MEMO = "_"
    def self.inst(type, *args)
      Statement.new(type:, value: args)
    end

    # LET = ->(name, value) { inst(:let, name, value) }
  end

  include Semantics
  RECALL = lambda do |item|
    # LET["_", item]
    Semantics.inst(:let, "_", item)
  end

  # The virtual machine for executing Aua ASTs.
  class VM
    extend Semantics

    def initialize(env = {})
      @env = env
    end

    def recall_primary(node)
      recollect = case node.type
                  when :int then Int.new(node.value)
                  when :float then Float.new(node.value)
                  when :bool then Bool.new(node.value)
                  when :str then Str.new(node.value)
                  else
                    puts "Unknown primary node type: #{node.type.inspect}"
                    Nihil.new
                  end
      [RECALL[recollect]]
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
      value = evaluate(value_node)
      @env[name] = value
      [Semantics.inst(:let, name, value)]
    end

    def translate_binop(node)
      op, left_node, right_node = node.value
      left = evaluate(left_node)
      right = evaluate(right_node)
      result =
        case op
        when :plus
          if left.is_a?(Int) && right.is_a?(Int)
            Int.new(left.value + right.value)
          elsif left.is_a?(Float) && right.is_a?(Float)
            Float.new(left.value + right.value)
          elsif left.is_a?(Str) && right.is_a?(Str)
            Str.new(left.value + right.value)
          else
            raise Error, "Unsupported operand types for +: #{left.class} and #{right.class}"
          end
        when :minus
          if left.is_a?(Int) && right.is_a?(Int)
            Int.new(left.value - right.value)
          elsif left.is_a?(Float) && right.is_a?(Float)
            Float.new(left.value - right.value)
          else
            raise Error, "Unsupported operand types for -: #{left.class} and #{right.class}"
          end
        when :star
          if left.is_a?(Int) && right.is_a?(Int)
            Int.new(left.value * right.value)
          elsif left.is_a?(Float) && right.is_a?(Float)
            Float.new(left.value * right.value)
          else
            raise Error, "Unsupported operand types for *: #{left.class} and #{right.class}"
          end
        when :slash
          if left.is_a?(Int) && right.is_a?(Int)
            raise Error, "Division by zero" if right.value == 0

            Int.new(left.value / right.value)
          elsif left.is_a?(Float) && right.is_a?(Float)
            raise Error, "Division by zero" if right.value == 0.0

            Float.new(left.value / right.value)
          else
            raise Error, "Unsupported operand types for /: #{left.class} and #{right.class}"
          end
        else
          raise Error, "Unknown binary operator: #{op}"
        end
      [RECALL[result]]
    end

    TRANSLATIONS = { nihil: [RECALL[Nihil.new]] }.freeze

    def translate(ast)
      return TRANSLATIONS[ast.type] if TRANSLATIONS.key?(ast.type)

      case ast.type
      when :int, :float, :bool, :str then recall_primary(ast)
      when :negate then translate_negation(ast)
      when :id then [RECALL[@env[ast.value] || Nihil.new]]
      when :assign then translate_assignment(ast)
      when :binop then translate_binop(ast)
      else
        raise Error, "Unknown AST node type: \\#{ast.type}"
      end
    end

    def evaluate(ast)
      ret = Nihil.new
      translate(ast).each do |stmt|
        ret = evaluate_one stmt
      end
      evaluate_one RECALL[ret]
      ret
    end

    def evaluate_one(stmt)
      # Evaluates a single statement in the VM.
      case stmt.type
      when :let
        name, value = stmt.value
        @env[name] = value
        value
      else
        raise Error, "Unknown statement type: #{stmt.type}"
      end
    rescue StandardError => e
      raise Error, "Evaluation error: #{e.message}"
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
    def parse(tokens) = Parse.ast tokens
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
        puts "#{step.name}: #{input.inspect}..."
        out = step.call(input)
        puts "#{step.name}: #{input.inspect} -> #{out.inspect}"
        out
      rescue Aua::Error => e
        puts "Error during processing: #{e.message}"
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
    interpreter = Interpreter.new
    interpreter.run(code)
  rescue Error => e
    puts "Aua interpreter error: #{e.message}"
    puts e.backtrace&.join("\n")
    # would be nice but we'd have to thread the position through the pipeline!
    raise e
  end
end
