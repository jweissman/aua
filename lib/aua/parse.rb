# frozen_string_literal: true

# Aua is a programming language and interpreter written in Ruby...
module Aua
  # The AST (Abstract Syntax Tree) node definitions for Aua.
  module AST
    # Represents a node in the abstract syntax tree (AST) of Aua.
    class Node < Data.define(:type, :value, :at)
      attr_reader :at

      def inspect = "#{type} (#{value.inspect} #{at})"
    end
  end

  # Grammar helpers for constructing AST nodes.
  module Grammar
    PRIMARY_NAMES = {
      lparen: :parens,
      minus: :negation,
      id: :id,
      int: :int,
      float: :float,
      bool: :bool,
      str: :str,
      nihil: :nihil,
      gen_lit: :generative_lit
    }.freeze

    # Operator precedence (higher number = higher precedence)
    BINARY_PRECEDENCE = {
      plus: 1, minus: 1,
      star: 2, slash: 2,
      pow: 3
    }.freeze

    def s(type, *values)
      normalized_values = normalize_maybe_list(values)
      at = if defined?(@current_token) && @current_token.respond_to?(:location) && @current_token.location
             @current_token.location
           else
             Aua::Text::Cursor.new(0, 0)
           end
      AST::Node.new(type:, value: normalized_values, at: at)
    end

    def normalize_maybe_list(values)
      return nil if values.empty?

      values.length == 1 ? values.first : values
    end

    # A class for parsing primitive values in Aua.
    class Primitives
      include Grammar

      def initialize(parse)
        @parse = parse
      end

      def parse_id      = parse_one(:id)
      def parse_int     = parse_one(:int)
      def parse_float   = parse_one(:float)
      def parse_bool    = parse_one(:bool)
      def parse_str     = parse_one(:str)
      def parse_nihil   = parse_one(:nihil)

      def parse_parens
        @parse.consume(:lparen)
        expr = @parse.send :parse_expression
        begin
          @parse.consume(:rparen)
        rescue Aua::Error
          raise Error, "Unmatched opening parenthesis"
        end
        expr
      end

      # Parses a unary minus expression.
      def parse_negation
        @parse.consume(:minus)
        raise Error, "Unexpected end of input after unary minus" if @parse.current_token.type == :eos

        unless %i[int float bool str id minus].include?(@parse.current_token.type)
          raise Error, "Unary minus must be followed by a literal or identifier, got #{@parse.current_token.type}"
        end

        operand = @parse.send :parse_primary
        s(:negate, operand)
      end

      def parse_generative_lit
        value = @parse.current_token.value
        @parse.consume(:gen_lit)
        s(:gen_lit, value)
      end

      private

      def parse_one(type)
        value = @parse.current_token.value
        @parse.consume(type)
        s(type, value)
      end
    end
  end

  extend Grammar
  NOTHING = s(:nihil)

  # A parser for the Aua language that builds an abstract syntax tree (AST).
  # Consumes tokens and produces an AST.
  class Parse
    attr_reader :current_token

    include Grammar

    def initialize(tokens)
      @tokens = tokens
      @buffer = [] # : Array[Syntax::Token | nil]

      advance
    end

    def tree
      ast = parse
      raise(Error, "Unexpected tokens after parsing: \\#{@current_token.inspect}") if unexpected_tokens?

      ast
    end

    def advance = @current_token = @buffer.shift || next_token

    def peek_token
      @buffer[0] = next_token if @buffer[0].nil?
    end

    def consume(expected_type, exact_value = nil)
      unless @current_token.type == expected_type
        raise Error, "Expected token type #{expected_type}, but got #{@current_token&.type || "EOF"}"
      end

      if exact_value && @current_token.value != exact_value
        raise Error, "Expected token value '#{exact_value}', but got '#{@current_token.value}'"
      end

      advance
    end

    def next_token
      @tokens.next
    rescue StopIteration
      # nil
      Syntax::Token.new(
        type: :eos, value: nil, at: @current_token&.at || Aua::Text::Cursor.new(0, 0)
      )
    end

    def unexpected_tokens?
      @length != @current_token_index && @current_token.type != :eos
    end

    private

    def parse = parse_expression

    # Parses an expression
    def parse_expression
      maybe_assignment = parse_assignment
      return maybe_assignment if maybe_assignment

      maybe_conditional = parse_conditional
      return maybe_conditional if maybe_conditional

      parse_binop
    end

    def parse_assignment
      return unless @current_token.type == :id && peek_token&.type == :equals

      id = @current_token
      consume(:id)
      name = id.value
      consume(:equals)
      value = parse_expression
      s(:assign, name, value)
    end

    def parse_conditional
      return unless @current_token.type == :keyword && @current_token.value == "if"

      consume(:keyword, "if")
      condition = parse_expression
      true_branch, false_branch = parse_condition_body
      s(:if, condition, true_branch, false_branch)
    end

    def parse_condition_body
      consume(:keyword, "then")
      true_branch = parse_expression
      false_branch = nil
      if @current_token.type == :keyword && @current_token.value == "else"
        consume(:keyword, "else")
        false_branch = parse_expression
      end
      [true_branch, false_branch]
    end

    def parse_binop(min_prec = 0)
      left = parse_primary
      left = consume_binary_op(left) while binary_op?(@current_token.type) && precedent?(@current_token.type, min_prec)
      left
    end

    def precedent?(operand, min_prec)
      return false unless BINARY_PRECEDENCE.key?(operand)

      BINARY_PRECEDENCE[operand] >= min_prec
    end

    def consume_binary_op(left)
      op_token = @current_token
      op = op_token.type
      prec = BINARY_PRECEDENCE[op]
      consume(op)
      next_min_prec = Set[:pow].include?(op) ? prec : prec + 1
      right = parse_binop(next_min_prec)
      s(:binop, op, left, right)
    end

    def binary_op?(type) = BINARY_PRECEDENCE.key?(type)

    def parse_primary
      raise Aua::Error, "No current token to parse" if @current_token.nil?
      raise Aua::Error, "Unexpected end of input while parsing primary expression" if @current_token.type == :eos

      primitives = Primitives.new(self)
      return primitives.send "parse_#{PRIMARY_NAMES[@current_token.type]}" if PRIMARY_NAMES.key?(@current_token.type)

      raise Error, "Unexpected token type: #{@current_token.type}"
    end

    def unexpected_token
      raise Error, "Unexpected token in primary expression: #{@current_token.type}"
    end
  end
end
