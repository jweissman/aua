# frozen_string_literal: true

# Aua is a programming language and interpreter written in Ruby...
module Aua
  # The AST (Abstract Syntax Tree) node definitions for Aua.
  module AST
    # Represents a node in the abstract syntax tree (AST) of Aua.
    class Node < Data.define(:type, :value, :at)
      attr_reader :at

      def inspect = "#{type} (#{value.inspect} #{at})"

      def ==(other)
        return false unless other.is_a?(Node)

        type == other.type && value == other.value
      end
    end
  end

  # Grammar helpers for constructing AST nodes.
  module Grammar
    PRIMARY_NAMES = {
      lparen: :parens,
      id: :id,
      int: :int,
      float: :float,
      bool: :bool,
      str: :str,
      nihil: :nihil,
      gen_lit: :generative_lit,

      simple_str: :simple_str
      # str_part: :str_part,
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

      def parse_id = parse_one(:id)
      def parse_int = parse_one(:int)
      def parse_float = parse_one(:float)
      def parse_bool = parse_one(:bool)
      def parse_str = parse_one(:str)

      def parse_nihil = parse_one(:nihil)
      def parse_simple_str = parse_one(:simple_str)

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
      Syntax::Token.new(
        type: :eof, value: nil, at: @current_token&.at || Aua::Text::Cursor.new(0, 0)
      )
    end

    def unexpected_tokens?
      @length != @current_token_index && @current_token.type != :eos
    end

    private

    def parse
      parse_statements
      # parse_expression
    end

    def parse_statements
      statements = []
      while @current_token.type != :eos && @current_token.type != :eof
        # Skip any leading :eos tokens (blank lines, etc.)
        advance while @current_token.type == :eos

        break if %i[eos].include?(@current_token.type)

        statement = parse_expression
        raise Error, "Unexpected end of input while parsing statements" if statement.nil?

        puts "Parsed statement: #{statement.inspect}" if Aua.testing?

        statements << statement

        # After a statement, consume any :eos tokens (semicolon or newline)
        while @current_token.type == :eos
          advance
        end
      end

      statements.size == 1 ? statements.first : s(:seq, statements.compact)
    end

    # Parses an expression
    def parse_expression
      puts "Parsing expression at #{current_token.at}" if Aua.testing?
      maybe_assignment = parse_assignment
      return maybe_assignment if maybe_assignment

      maybe_conditional = parse_conditional
      return maybe_conditional if maybe_conditional

      maybe_command = parse_command
      return maybe_command if maybe_command

      parse_binop
    end

    # Parses a command or function call: id arg1 arg2 ...
    def parse_command
      return unless @current_token.type == :id

      id_token = @current_token
      puts "Parsing command with ID: #{id_token.value}" if Aua.testing?
      args = [] # : Array[AST::Node]
      save_token = @current_token
      save_buffer = @buffer.dup
      consume(:id)
      puts " - Consumed ID: #{id_token.value}" if Aua.testing?

      # debugger if Aua.testing?

      # Accept one or more primary expressions as arguments (space-separated)
      while PRIMARY_NAMES.key?(@current_token.type)
        args << Primitives.new(self).send("parse_#{PRIMARY_NAMES[@current_token.type]}")
        if @current_token.type == :comma
          consume(:comma)
          puts " - Consumed comma, expecting more args" if Aua.testing?
        elsif [:eos, :eof].include?(@current_token.type)
          puts " - End of arguments reached" if Aua.testing?
          break
        else
          raise Error, "Unexpected token while parsing arguments: #{@current_token.type}"
        end
      end

      puts " - Parsed arguments: #{args.inspect}" if Aua.testing?
      if args.empty?
        # Not a call, restore state and return nil
        @current_token = save_token
        @buffer = save_buffer
        return nil
      end
      puts " - Call recognized with ID: #{id_token.value} and args: #{args.inspect}" if Aua.testing?
      s(:call, id_token.value, args)
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
      left = parse_unary
      raise Error, "Unexpected end of input while parsing binary operation" if left.nil?

      left = consume_binary_op(left) while binary_op?(@current_token.type) && precedent?(@current_token.type, min_prec)
      left
    end

    def parse_unary
      if @current_token.type == :minus
        consume(:minus)
        operand = parse_unary
        s(:negate, operand)
      else
        parse_primary
      end
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

      # Handle structured/interpolated strings
      if @current_token.type == :str_part
        return parse_structured_str # @type var parts: Array[AST::Node]
      end

      primitives = Primitives.new(self)
      return primitives.send "parse_#{PRIMARY_NAMES[@current_token.type]}" if PRIMARY_NAMES.key?(@current_token.type)

      raise Error, "Unexpected token type: #{@current_token.type}"
    end

    # Parses a structured/interpolated string
    # @type method parse_structured_str: () -> AST::Node
    def parse_structured_str
      parts = [] # Array[AST::Node]
      while true
        if @current_token.type == :str_part
          parts << s(:str, @current_token.value)
          advance
        elsif @current_token.type == :interpolation_start
          advance
          expr = parse_expression
          parts << expr
          if @current_token.type == :interpolation_end
            advance
          else
            raise Error, "Expected interpolation_end, got #{@current_token.type}"
          end
        elsif @current_token.type == :str_end
          advance
          break
        else
          if current_token.type == :eof
            raise Error, "Unterminated string literal #{current_token.at}"
          end
          raise Error, "Unexpected token in structured string: #{current_token.type} #{current_token.at}"
        end
      end
      return s(:str, parts.first.value) if parts.size == 1 && parts.first.type == :str

      s(:structured_str, parts)
    end
  end
end
